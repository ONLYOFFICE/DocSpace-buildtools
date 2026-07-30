#!/bin/bash
# Usage:
#   docker-utils.sh test-install [MODE_ARGS]  — download, patch and run install-Docker.sh
#   docker-utils.sh check-services SERVICES   — verify all services were created
#   docker-utils.sh status                    — print health status for all containers
#   docker-utils.sh logs [TAIL]               — print logs for unhealthy containers and exit on failure
#   docker-utils.sh shellcheck                — run ShellCheck on all docker scripts
#   docker-utils.sh smoke-test                — run browser smoke tests via the selenium container (env: LICENSE)

set -e

COMMAND="${1:-status}"
TAIL="${2:-30}"

print_status() {
  while IFS= read -r CONTAINER; do
    local STATUS COLOR
    STATUS=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}" "$CONTAINER")
    case "$STATUS" in
      healthy)          COLOR="\033[0;32m" ;;
      "no healthcheck") COLOR="\033[0;33m" ;;
      *)                COLOR="\033[0;31m"; echo "container_status=red" >> "$GITHUB_ENV" ;;
    esac
    printf "%-50s ${COLOR}%s\033[0m\n" "${CONTAINER}:" "$STATUS"
  done < <(docker ps --all --format "{{.Names}}")
}

print_logs() {
  while IFS= read -r CONTAINER; do
    local STATUS
    STATUS=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}" "$CONTAINER")
    case "$STATUS" in
      healthy | "no healthcheck") continue ;;
    esac
    echo "Logs for container $CONTAINER:"
    docker logs --tail "$TAIL" "$CONTAINER" | sed "s/^/\t/g"
  done < <(docker ps --all --format "{{.Names}}")
  case "${container_status:-}" in
    timeout) echo "::error:: Timeout reached. Not all containers are running."; exit 1 ;;
    red)     echo "::error:: One or more containers have status 'red'. Job will fail."; exit 1 ;;
  esac
}

test_install() {
  local MODE_ARGS="${1:-}"
  local INSTALL_SCRIPT="${GITHUB_WORKSPACE}/install/OneClickInstall/install-Docker.sh"
  local PATCHED_SCRIPT; PATCHED_SCRIPT=$(mktemp --suffix=.sh)
  cp "$INSTALL_SCRIPT" "$PATCHED_SCRIPT"

  local INSTALL_CMD="sudo bash $PATCHED_SCRIPT -skiphc true -noni true -gb $GITHUB_REF_NAME $MODE_ARGS"
  [ "${IS_4TESTING:-true}" != "false" ] && \
    INSTALL_CMD="$INSTALL_CMD -s 4testing- -un $DOCKERHUB_USERNAME_PAT -p $DOCKERHUB_TOKEN_PAT"
  [ -n "${DOCKER_TAG:-}" ] && INSTALL_CMD="$INSTALL_CMD -dsv $DOCKER_TAG"

  sed -i -e "1i set -x" -e "/DOCKER_COMPOSE.*up -d/ s/$/ --quiet-pull/" "$PATCHED_SCRIPT"

  eval "$INSTALL_CMD" || exit $?
  echo "Waiting for containers..." && \
    timeout 300 bash -c 'while docker ps | grep -q "starting"; do sleep 5; done' || \
    echo "container_status=timeout" >> "$GITHUB_ENV"
}

check_services() {
  local SERVICES_STR="$1"
  read -ra SERVICES <<< "$SERVICES_STR"
  local YML_ARGS=() MISSING_COUNT=0
  for SERVICE in "${SERVICES[@]}"; do YML_ARGS+=( -f "/app/onlyoffice/${SERVICE}.yml" ); done
  for SVC in $(docker compose "${YML_ARGS[@]}" config --services); do
    docker compose "${YML_ARGS[@]}" ps "$SVC" | grep -q "$SVC" || \
      { echo "::error::$SVC was not created"; MISSING_COUNT=$((MISSING_COUNT+1)); }
  done
  [ "$MISSING_COUNT" -gt 0 ] && { echo "::error::$MISSING_COUNT service(s) were not created."; exit 1; } || true
}

run_shellcheck() {
  set -eux
  sudo apt-get install -y shellcheck
  find install/docker -type f -name "*.sh" | cat - <(echo "install/OneClickInstall/install-Docker.sh") \
    | xargs shellcheck --exclude="$(awk '!/^#|^$/ {print $1}' tests/lint/sc_ignore | paste -sd ",")" \
      --severity=warning | tee sc_output
  awk '/\(warning\):/ {w++} /\(error\):/ {e++} END {if (w+e) printf "::warning ::ShellCheck detected %d warnings and %d errors\n", w+0, e+0}' sc_output
}


smoke_test() {
  PIP_BREAK_SYSTEM_PACKAGES=1 pip install -q --disable-pip-version-check -r tests/smoke/requirements.txt

  # arm64 runners have no Chrome/chromedriver builds — fall back to the selenium container there
  if ! command -v google-chrome >/dev/null; then
    docker pull -q selenium/standalone-chromium:latest
    docker run -d --name selenium --network host --shm-size 2g selenium/standalone-chromium:latest
    timeout 60 bash -c 'until curl -sf http://localhost:4444/status | grep -qE "\"ready\":\s*true"; do sleep 2; done'       || { echo "::error::selenium container is not ready"; exit 1; }
    export SELENIUM_REMOTE_URL=http://localhost:4444
  fi

  python3 -m pytest tests/smoke/test_docspace_smoke.py -v -s
}

case "$COMMAND" in
  test-install)   test_install "$2" ;;
  check-services) check_services "$2" ;;
  status)         print_status ;;
  logs)           print_logs ;;
  shellcheck)     run_shellcheck ;;
  smoke-test)     smoke_test ;;
  *)              echo "Unknown command: $COMMAND"; exit 1 ;;
esac
