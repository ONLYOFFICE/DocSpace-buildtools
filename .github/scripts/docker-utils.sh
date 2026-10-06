#!/bin/bash
# Usage:
#   docker-utils.sh test-install [MODE_ARGS]  — download, patch and run install-Docker.sh
#   docker-utils.sh check-services SERVICES   — verify all services were created ("auto": by the detected mode)
#   docker-utils.sh status                    — print health status for all containers
#   docker-utils.sh logs [TAIL]               — print logs for unhealthy containers and exit on failure
#   docker-utils.sh shellcheck                — run ShellCheck on all docker scripts
#   docker-utils.sh smoke-test [PYTEST_ARGS]  — run browser smoke tests (env: LICENSE, SMOKE_SUMMARY_TITLE)
#   docker-utils.sh restart SERVICES          — recreate the installed containers, keeping volumes
#   docker-utils.sh log-audit                 — fail on OOM kills and crashed containers, warn on restarts and log errors
#   docker-utils.sh summary                   — add a container table to the job summary
#   docker-utils.sh install-previous          — install the latest released DocSpace (env: PREVIOUS_VERSION)
#   docker-utils.sh update-install [ARGS]     — update the installed release with install-Docker.sh from this branch
#   docker-utils.sh verify-update             — check that no container still runs the previous release
#   docker-utils.sh compose-validate          — validate every shipped Compose combination

set -e

COMMAND="${1:-status}"
TAIL="${2:-30}"
INSTALL_DIR="/app/onlyoffice"
STATE_DIR="${RUNNER_TEMP:-/tmp}"

print_status() {
  while IFS= read -r CONTAINER; do
    local STATUS COLOR
    STATUS=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}" "$CONTAINER")
    case "$STATUS" in
      healthy)          COLOR="\033[0;32m" ;;
      starting | "no healthcheck") COLOR="\033[0;33m" ;;
      *)                COLOR="\033[0;31m" ;;
    esac
    printf "%-50s ${COLOR}%s\033[0m\n" "${CONTAINER}:" "$STATUS"
  done < <(docker ps --all --format "{{.Names}}")
}

print_logs() {
  local FAILED=0
  while IFS= read -r CONTAINER; do
    local STATUS
    STATUS=$(docker inspect --format="{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}" "$CONTAINER")
    case "$STATUS" in
      healthy | "no healthcheck") continue ;;
    esac
    FAILED=1
    echo "Logs for container $CONTAINER:"
    docker logs --tail "$TAIL" "$CONTAINER" | sed "s/^/\t/g"
  done < <(docker ps --all --format "{{.Names}}")
  if [ "$FAILED" -ne 0 ]; then
    echo "::error::One or more containers are still not healthy."
    return 1
  fi
}

summary_append() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat >> "$GITHUB_STEP_SUMMARY"
  else
    cat > /dev/null
  fi
}

# Pads a summary title with non-breaking spaces to the width used by the smoke test lines
summary_title() {
  local TEXT="$1" PADDING="" COUNT
  for (( COUNT=${#TEXT}; COUNT<34; COUNT++ )); do PADDING+="&nbsp;"; done
  printf '%s%s' "$TEXT" "$PADDING"
}

wait_for_containers() {
  echo "Waiting for containers..."
  if ! timeout 300 bash -c 'while docker ps | grep -q "starting"; do sleep 5; done'; then
    echo "::warning::Timed out waiting for container health checks; checking live status after the smoke test."
  fi
}

env_value() {
  sudo grep -E "^\s*$1=" "${INSTALL_DIR}/.env" 2>/dev/null | tail -n 1 \
    | sed -E -e 's/\r$//' -e 's/^[^=]*=//' -e 's/^[[:space:]]+|[[:space:]]+$//g' -e 's/^"(.*)"$/\1/'
}

# Fills the caller's YML_ARGS with -f options for the given service names
compose_args() {
  local SERVICE
  YML_ARGS=()
  for SERVICE in $1; do YML_ARGS+=( -f "${INSTALL_DIR}/${SERVICE}.yml" ); done
  # the installer adds these mounts when it adopted an existing Document Server
  case " $1 " in
    *" ds "* | *" docker-compose "*) [ -f "${INSTALL_DIR}/config/ds-mounts.json" ] && YML_ARGS+=( -f "${INSTALL_DIR}/config/ds-mounts.json" ) ;;
  esac
  return 0
}

run_installer() {
  local PATCHED_SCRIPT; PATCHED_SCRIPT=$(mktemp --suffix=.sh)
  cp "${GITHUB_WORKSPACE}/install/OneClickInstall/install-Docker.sh" "$PATCHED_SCRIPT"

  local INSTALL_CMD="sudo bash $PATCHED_SCRIPT -skiphc true -noni true -gb $GITHUB_REF_NAME $*"
  [ "${IS_4TESTING:-true}" != "false" ] && \
    INSTALL_CMD="$INSTALL_CMD -s 4testing- -un $DOCKERHUB_USERNAME_PAT -p $DOCKERHUB_TOKEN_PAT"
  [ -n "${DOCKER_TAG:-}" ] && INSTALL_CMD="$INSTALL_CMD -dsv $DOCKER_TAG"

  sed -i -e "1i set -x" -e "/DOCKER_COMPOSE.*up -d/ s/$/ --quiet-pull/" "$PATCHED_SCRIPT"

  eval "$INSTALL_CMD" || exit $?
  wait_for_containers
}

test_install() {
  run_installer "${1:-}"
}

check_services() {
  local SERVICES_STR="$1"
  [ "$SERVICES_STR" = "auto" ] && SERVICES_STR=$(default_services)
  local YML_ARGS=() MISSING_COUNT=0 SVC_LIST SERVICE
  compose_args "$SERVICES_STR"
  SVC_LIST=$(sudo docker compose "${YML_ARGS[@]}" config --services) || \
    { echo "::error::Could not read the installed Compose configuration."; return 1; }
  [ -n "$SVC_LIST" ] || { echo "::error::No services found in the Compose configuration."; return 1; }
  for SERVICE in $SVC_LIST; do
    sudo docker compose "${YML_ARGS[@]}" ps --all "$SERVICE" | grep -Fq "$SERVICE" || \
      { echo "::error::$SERVICE was not created"; MISSING_COUNT=$((MISSING_COUNT+1)); }
  done
  [ "$MISSING_COUNT" -gt 0 ] && { echo "::error::$MISSING_COUNT service(s) were not created."; exit 1; } || true
}

run_shellcheck() {
  set -eux
  sudo apt-get install -y shellcheck
  find install/docker -type f -name "*.sh" | cat - <(printf '%s\n' install/OneClickInstall/install-Docker{,-docs}.sh .github/scripts/docker-utils.sh) \
    | xargs shellcheck --exclude="$(awk '!/^#|^$/ {print $1}' tests/lint/sc_ignore | paste -sd ",")" \
      --severity=warning | tee sc_output
  awk '/\(warning\):/ {w++} /\(error\):/ {e++} END {if (w+e) printf "::warning ::ShellCheck detected %d warnings and %d errors\n", w+0, e+0}' sc_output
}

# Services of the installed deployment, as the matrix of the install workflow lists them
default_services() {
  case "$(detect_mode)" in
    standalone) echo "docker-compose" ;;
    stack)      echo "apps-stack dashboards db ds fluent opensearch proxy rabbitmq redis" ;;
    *)          echo "apps healthchecks identity notify dashboards db ds fluent opensearch proxy rabbitmq redis" ;;
  esac
}

detect_mode() {
  if docker ps --all --format '{{.Names}}' | grep -qx 'onlyoffice-apps'; then
    echo standalone
  elif docker ps --all --format '{{.Names}}' | grep -qx 'onlyoffice-dotnet-services'; then
    echo stack
  else
    echo microservices
  fi
}

smoke_test() {
  # later phases of the same job find the packages already installed
  python3 -c 'import pytest, selenium' 2>/dev/null || \
    PIP_BREAK_SYSTEM_PACKAGES=1 pip install -q --disable-pip-version-check -r tests/smoke/requirements.txt

  # arm64 runners have no Chrome/chromedriver builds — fall back to the selenium container there
  if ! command -v google-chrome >/dev/null; then
    # later phases reuse the container started by the first one
    if ! docker ps --all --format '{{.Names}}' | grep -qx selenium; then
      docker pull -q selenium/standalone-chromium:latest
      # the co-editing test drives two browsers at once
      docker run -d --name selenium --network host --shm-size 2g -e SE_NODE_MAX_SESSIONS=2 -e SE_NODE_OVERRIDE_MAX_SESSIONS=true selenium/standalone-chromium:latest
    fi
    timeout 60 bash -c 'until curl -sf http://localhost:4444/status | grep -qE "\"ready\":\s*true"; do sleep 2; done'       || { echo "::error::selenium container is not ready"; exit 1; }
    export SELENIUM_REMOTE_URL=http://localhost:4444
  fi

  DEPLOYMENT_MODE=$(detect_mode)
  export DEPLOYMENT_MODE
  export SMOKE_STATE_FILE="${SMOKE_STATE_FILE:-${STATE_DIR}/smoke-state.json}"
  export SMOKE_SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-}"
  if [ "$DEPLOYMENT_MODE" != "standalone" ]; then
    DASHBOARDS_USERNAME=$(env_value DASHBOARDS_USERNAME)
    DASHBOARDS_PASSWORD=$(env_value DASHBOARDS_PASSWORD)
    export DASHBOARDS_USERNAME DASHBOARDS_PASSWORD
  fi

  python3 -m pytest tests/smoke/smoke_test.py -v -s "$@"
}

restart_services() {
  local YML_ARGS=()
  compose_args "$1"
  echo "Recreating the containers (volumes are kept)..."
  sudo docker compose "${YML_ARGS[@]}" down || { echo "::error::docker compose down failed."; return 1; }
  sudo docker compose "${YML_ARGS[@]}" up -d --quiet-pull || { echo "::error::docker compose up failed."; return 1; }
  wait_for_containers
}

log_audit() {
  # log levels: NLog/Java print ERROR and FATAL, Fluent Bit prints [error]; plain words like "fatal" do not count
  local FAILED=0 PATTERN='(^|[^A-Za-z])(ERROR|FATAL)([^A-Za-z]|$)|\[(error|fatal)\]'
  # crash signatures that carry no log level, matched in any case
  local CRASH_PATTERN='panic|unhandled exception|outofmemory|segmentation fault'
  local CONTAINER_IDS=() NAME RESTARTS OOM_KILLED STATE EXIT_CODE LOG_LINES ERROR_LINES MATCHES SAMPLE
  local ROWS=()
  mapfile -t CONTAINER_IDS < <(docker ps --all --quiet --filter "name=^onlyoffice")
  [ "${#CONTAINER_IDS[@]}" -gt 0 ] || { echo "::error::No containers to audit."; return 1; }

  while read -r NAME RESTARTS OOM_KILLED STATE EXIT_CODE; do
    NAME="${NAME#/}"
    if [ "$OOM_KILLED" = "true" ]; then
      echo "::error::$NAME was killed by the OOM killer."
      ROWS+=("| \`$NAME\` | ❌ | OOM killed |")
      FAILED=1
    fi
    if [ "$STATE" = "exited" ] && [ "$EXIT_CODE" != "0" ]; then
      echo "::error::$NAME exited with code $EXIT_CODE."
      ROWS+=("| \`$NAME\` | ❌ | exited with code $EXIT_CODE |")
      FAILED=1
    fi
    if [ "$RESTARTS" -gt 0 ]; then
      echo "::warning::$NAME was restarted $RESTARTS time(s)."
      ROWS+=("| \`$NAME\` | ⚠️ | restarted $RESTARTS time(s) |")
    fi
    # OpenSearch prints ERROR lines of its own plugins during a normal start
    case "$NAME" in *-opensearch) continue ;; esac
    LOG_LINES=$(docker logs --tail 2000 "$NAME" 2>&1)
    ERROR_LINES=$({ grep -E "$PATTERN" <<< "$LOG_LINES"; grep -iE "$CRASH_PATTERN" <<< "$LOG_LINES"; } | awk '!seen[$0]++' || true)
    MATCHES=$(grep -c . <<< "$ERROR_LINES" || true)
    if [ "$MATCHES" -gt 0 ]; then
      # the first line goes to the summary without characters that break a table cell
      SAMPLE=$(head -n 1 <<< "$ERROR_LINES" | cut -c1-150 | tr '|`' '  ')
      echo "::warning::$NAME logged $MATCHES error line(s), e.g. $SAMPLE"
      ROWS+=("| \`$NAME\` | ⚠️ | $MATCHES error line(s), e.g. $SAMPLE |")
    fi
  done < <(docker inspect --format '{{.Name}} {{.RestartCount}} {{.State.OOMKilled}} {{.State.Status}} {{.State.ExitCode}}' "${CONTAINER_IDS[@]}")

  # kept until the summary step, which prints it right before the container table
  {
    if [ "${#ROWS[@]}" -eq 0 ]; then
      # a collapsible line like the others, so that all lines start at the same position
      echo "<details><summary><code>$(summary_title "Container audit") — ✅ clean</code></summary>"
      echo
      echo "No OOM kills, crashes, restarts or error lines in the last 2000 log lines of each container."
      echo
      echo "</details>"
    else
      echo "<details open><summary><code>$(summary_title "Container audit") — $([ "$FAILED" -ne 0 ] && echo "❌" || echo "⚠️") ${#ROWS[@]} finding(s)</code></summary>"
      echo
      echo "| Container | | Finding |"
      echo "|---|---|---|"
      printf '%s\n' "${ROWS[@]}"
      echo
      echo "</details>"
    fi
    echo
  } > "${STATE_DIR}/audit-summary.md"

  return "$FAILED"
}

write_summary() {
  local NAME IMAGE STATE HEALTH RESTARTS EXIT_CODE ROW TOTAL=0 HEALTHY=0
  if [ -f "${STATE_DIR}/audit-summary.md" ]; then
    summary_append < "${STATE_DIR}/audit-summary.md"
    rm -f "${STATE_DIR}/audit-summary.md"
  fi
  local OK_ROWS=() PROBLEM_ROWS=()
  while IFS='|' read -r NAME IMAGE STATE HEALTH RESTARTS EXIT_CODE; do
    [ -n "$NAME" ] || continue
    TOTAL=$((TOTAL+1))
    ROW="| \`$NAME\` | $IMAGE | $STATE | $HEALTH | $RESTARTS |"
    # a finished one-shot container (migration runner) is fine, a running unhealthy or restarted one is not
    if { [ "$STATE" = "running" ] && [ "$HEALTH" != "healthy" ] && [ "$HEALTH" != "-" ]; } \
        || { [ "$STATE" != "running" ] && [ "$EXIT_CODE" != "0" ]; } || [ "$RESTARTS" -gt 0 ]; then
      PROBLEM_ROWS+=("$ROW")
    else
      OK_ROWS+=("$ROW")
      HEALTHY=$((HEALTHY+1))
    fi
  done < <(docker ps --all --quiet | xargs -r docker inspect --format \
    '{{slice .Name 1}}|{{.Config.Image}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}|{{.RestartCount}}|{{.State.ExitCode}}')

  {
    # open only when something is wrong; the problem rows come first
    echo "<details$([ "${#PROBLEM_ROWS[@]}" -gt 0 ] && echo " open")><summary><code>$(summary_title "Containers") — ${HEALTHY} of ${TOTAL} are fine</code></summary>"
    echo
    echo "| Container | Image | State | Health | Restarts |"
    echo "|---|---|---|---|---|"
    [ "${#PROBLEM_ROWS[@]}" -eq 0 ] || printf '%s\n' "${PROBLEM_ROWS[@]}"
    printf '%s\n' "${OK_ROWS[@]}"
    echo
    echo "</details>"
    echo
  } | summary_append
}

install_previous() {
  local OLD_SCRIPT; OLD_SCRIPT=$(mktemp --suffix=.sh)
  local ARGS=(-skiphc true -noni true)
  [ -n "${PREVIOUS_VERSION:-}" ] && ARGS+=(-dsv "$PREVIOUS_VERSION")

  # the latest release still ships under the DocSpace name
  curl -fsSL --retry 3 --retry-delay 2 "https://download.onlyoffice.com/docspace/install-Docker.sh" -o "$OLD_SCRIPT" || \
    { echo "::error::Could not download the released install-Docker.sh."; return 1; }
  sudo bash "$OLD_SCRIPT" "${ARGS[@]}" || { echo "::error::The released installer failed."; return 1; }
  wait_for_containers

  local IMAGE
  IMAGE=$(docker inspect --format '{{.Config.Image}}' onlyoffice-api 2>/dev/null || true)
  [ -n "$IMAGE" ] || { echo "::error::onlyoffice-api was not created by the released installer."; return 1; }
  echo "${IMAGE##*:}" > "${STATE_DIR}/previous-image-tag"
  echo "Installed release: ${IMAGE}"
}

update_install() {
  run_installer "-u true" "${1:-}"
}

verify_update() {
  local OLD_TAG NEW_TAG LEFTOVERS
  OLD_TAG=$(cat "${STATE_DIR}/previous-image-tag")
  NEW_TAG=$(env_value DOCKER_TAG)
  echo "Previous release tag: ${OLD_TAG}, installed tag: ${NEW_TAG}"
  { [ -n "$NEW_TAG" ] && [ "$NEW_TAG" != "$OLD_TAG" ]; } || \
    { echo "::error::DOCKER_TAG did not change after the update (${OLD_TAG} -> ${NEW_TAG})."; return 1; }
  # compare the tag as a plain string: its dots must not act as regex wildcards
  LEFTOVERS=$(docker ps --all --format '{{.Names}} {{.Image}}' \
    | awk -v suffix=":${OLD_TAG}" 'substr($2, length($2) - length(suffix) + 1) == suffix')
  if [ -n "$LEFTOVERS" ]; then
    echo "::error::Containers still use the previous release:"
    echo "$LEFTOVERS"
    return 1
  fi
  {
    echo "<details><summary><code>$(summary_title "Update") — ${OLD_TAG} → ${NEW_TAG}</code></summary>"
    echo
    echo "No container runs the previous release any more."
    echo
    echo "</details>"
    echo
  } | summary_append
}

compose_validate() {
  local WORK_DIR; WORK_DIR=$(mktemp -d)
  local FAILED=0
  cp -r install/docker/. "$WORK_DIR/"
  # standalone reads its own .env from the installed directory
  cp "$WORK_DIR/.env" "$WORK_DIR/standalone/.env"

  validate_combination() {
    local NAME="$1" ENV_DIR="$2"; shift 2
    local ARGS=() SERVICE OUTPUT
    for SERVICE in "$@"; do ARGS+=( -f "$WORK_DIR/${ENV_DIR}${SERVICE}.yml" ); done
    if OUTPUT=$(docker compose --project-directory "$WORK_DIR/${ENV_DIR}" "${ARGS[@]}" config --quiet 2>&1); then
      echo "ok: $NAME"
    else
      echo "::error::Compose combination '$NAME' is invalid:"
      echo "$OUTPUT"
      FAILED=1
    fi
  }

  local INFRA=(db redis rabbitmq opensearch ds fluent dashboards)
  validate_combination stack "" apps-stack proxy "${INFRA[@]}"
  validate_combination microservices "" migration-runner identity notify apps healthchecks proxy "${INFRA[@]}"
  validate_combination stack-ssl "" apps-stack proxy-ssl "${INFRA[@]}"
  validate_combination microservices-ssl "" migration-runner identity notify apps healthchecks proxy-ssl "${INFRA[@]}"

  if docker compose --project-directory "$WORK_DIR/standalone" -f "$WORK_DIR/standalone/docker-compose.yml" \
      --profile mysql --profile opensearch --profile docs config --quiet; then
    echo "ok: standalone"
  else
    echo "::error::Compose combination 'standalone' is invalid."
    FAILED=1
  fi
  return "$FAILED"
}

case "$COMMAND" in
  test-install)     test_install "$2" ;;
  check-services)   check_services "$2" ;;
  status)           print_status ;;
  logs)             print_logs ;;
  shellcheck)       run_shellcheck ;;
  smoke-test)       shift; smoke_test "$@" ;;
  restart)          restart_services "$2" ;;
  log-audit)        log_audit ;;
  summary)          write_summary ;;
  install-previous) install_previous ;;
  update-install)   update_install "$2" ;;
  verify-update)    verify_update ;;
  compose-validate) compose_validate ;;
  *)                echo "Unknown command: $COMMAND"; exit 1 ;;
esac
