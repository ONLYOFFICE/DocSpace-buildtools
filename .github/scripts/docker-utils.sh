#!/bin/bash
# Usage:
#   docker-utils.sh test-install [MODE_ARGS]  — download, patch and run install-Docker.sh
#   docker-utils.sh check-services SERVICES   — verify all services were created
#   docker-utils.sh status                    — print health status for all containers
#   docker-utils.sh logs [TAIL]               — print logs for unhealthy containers and exit on failure
#   docker-utils.sh shellcheck                — run ShellCheck on all docker scripts
#   docker-utils.sh start-preview             — resolve tag, patch .env and start preview stack (run from preview dir)

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

start_preview() {
  set -x
  if [ "${IS_4TESTING:-true}" != "false" ]; then
    sed -i 's~^\(\s*DOCKER_IMAGE_PREFIX=\).*~\14testing-docspace~' .env
  fi

  if [ -z "${DOCKER_TAG:-}" ]; then
    local ARCH; ARCH="$(uname -m | sed -E 's/^(x86_64|amd64)$/amd64/; s/^(aarch64|arm64)$/arm64/')"
    local IMAGE_PREFIX; IMAGE_PREFIX="$(awk -F= '/^[[:space:]]*DOCKER_IMAGE_PREFIX=/ {print $2}' .env)"
    local TAG_REGEX='^[0-9]+\.[0-9]+(\.[0-9]+){0,2}$'
    if [ "${GITHUB_REF_NAME:-}" = "develop" ] && [ "${IS_4TESTING:-true}" != "false" ]; then
      TAG_REGEX='^develop\.[0-9]+$'
    fi

    local AUTH_HEADER=()
    set +x
    if [ -n "${DOCKERHUB_USERNAME_PAT:-}" ] && [ -n "${DOCKERHUB_TOKEN_PAT:-}" ]; then
      local DOCKERHUB_JWT
      DOCKERHUB_JWT=$(curl -fsSL -X POST "https://hub.docker.com/v2/users/login" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"${DOCKERHUB_USERNAME_PAT}\",\"password\":\"${DOCKERHUB_TOKEN_PAT}\"}" \
        | jq -r '.token // empty' || true)
      [ -n "$DOCKERHUB_JWT" ] || { set -x; echo "::error::Docker Hub PAT login failed"; exit 1; }
      AUTH_HEADER=(-H "Authorization: JWT ${DOCKERHUB_JWT}")
    fi
    DOCKER_TAG=$(curl -fsSL "${AUTH_HEADER[@]}" \
      "https://hub.docker.com/v2/repositories/onlyoffice/${IMAGE_PREFIX}-preview/tags?page_size=100" \
      | jq -r '.results[] | select(.name | test("^(?!99\\.).*")) | select(.images[]?.architecture=="'"$ARCH"'") | .name // empty' \
      | grep -E "$TAG_REGEX" | sort -V | tail -n 1)
    set -x
    [ -n "$DOCKER_TAG" ] || { echo "::error::Failed to get Docker tag for onlyoffice/${IMAGE_PREFIX}-preview"; exit 1; }
  fi
  sed -i "s~^\(\s*DOCKER_TAG=\).*~\1${DOCKER_TAG}~" .env

  docker compose up -d --quiet-pull --no-build
  echo "Waiting for containers to become ready..."
  timeout 600 bash -c 'while docker ps --format "{{.Status}}" | grep -q "health: starting"; do sleep 5; done' \
    || echo "container_status=timeout" >> "$GITHUB_ENV"
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

case "$COMMAND" in
  test-install)   test_install "$2" ;;
  check-services) check_services "$2" ;;
  status)         print_status ;;
  logs)           print_logs ;;
  shellcheck)     run_shellcheck ;;
  start-preview)  start_preview ;;
  *)              echo "Unknown command: $COMMAND"; exit 1 ;;
esac
