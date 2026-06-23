#!/bin/bash

set -e

export TERM=xterm-256color

get_colors() {
    export LINE_SEPARATOR="-----------------------------------------"
    export COLOR_BLUE=$'\e[34m' COLOR_GREEN=$'\e[32m' COLOR_RED=$'\e[31m' COLOR_RESET=$'\e[0m' COLOR_YELLOW=$'\e[33m'
}

healthcheck_systemd_services() {
  mapfile -t SERVICES_SYSTEMD < <(awk '/SERVICE_NAME=\(/{flag=1; next} /\)/{flag=0} flag' "build.sh" | sed -E 's/^[[:space:]]*|[[:space:]]*$//g; s/^/docspace-/; s/$/.service/')
  SERVICES_SYSTEMD+=("ds-converter.service" "ds-docservice.service" "ds-metrics.service")

  for service in "${SERVICES_SYSTEMD[@]}"; do
    [[ "$service" == *migration* ]] && continue;
    if systemctl is-active --quiet "${service}"; then
      echo "${COLOR_GREEN}[OK] Service ${service} is running${COLOR_RESET}"
    else
      echo "${COLOR_RED}[FAILED] Service ${service} is not running${COLOR_RESET}"
      echo "::error::Service ${service} is not running"
      return 1
    fi
  done
}

healthcheck_dead_systemd_services() {
  mapfile -t SERVICES_SYSTEMD_DEAD < <(
    {
      find /etc/systemd/system -type l -name 'docspace-*.service' ! -exec test -e {} \; -print
      systemctl list-units --type=service --all --no-legend | awk '$1 ~ /^docspace-.*\.service$/ && $2 == "not-found" {print $1}'
    } | sort -u
  )

  if [ "${#SERVICES_SYSTEMD_DEAD[@]}" -gt 0 ]; then
    echo "${COLOR_RED}[FAILED] Dead systemd services found:${COLOR_RESET}"
    printf '%s\n' "${SERVICES_SYSTEMD_DEAD[@]}"
    echo "::error::Dead systemd services found"
    return 1
  fi

  echo "${COLOR_GREEN}[OK] No dead systemd services found${COLOR_RESET}"
}

service_exists() {
  systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q .
}

dependency_logs() {
  local SERVICE
  local SERVICES=(
    opensearch.service
    opensearch-dashboards.service
    mysqld.service
    mysql.service
    mariadb.service
    rabbitmq-server.service
    redis.service
    redis-server.service
    valkey.service
    openresty.service
    fluent-bit.service
  )

  echo "$LINE_SEPARATOR"
  echo "${COLOR_BLUE}DEPENDENCY DIAGNOSTICS${COLOR_RESET}"
  echo "$LINE_SEPARATOR"

  for SERVICE in "${SERVICES[@]}"; do
    service_exists "$SERVICE" || continue

    echo "$LINE_SEPARATOR"
    echo "${COLOR_GREEN}Status for systemd service: $SERVICE${COLOR_RESET}"
    echo "$LINE_SEPARATOR"
    systemctl status "$SERVICE" -l --no-pager || true

    echo "$LINE_SEPARATOR"
    echo "${COLOR_GREEN}Journal for systemd service: $SERVICE${COLOR_RESET}"
    echo "$LINE_SEPARATOR"
    journalctl -u "$SERVICE" -b -n 50 --no-pager || true
  done
}

services_logs() {
  mapfile -t SERVICES_SYSTEMD < <(awk '/SERVICE_NAME=\(/{flag=1; next} /\)/{flag=0} flag' "build.sh" | sed -E 's/^[[:space:]]*|[[:space:]]*$//g; s/^/docspace-/; s/$/.service/')
  SERVICES_SYSTEMD+=("ds-converter.service" "ds-docservice.service" "ds-metrics.service")

  echo $LINE_SEPARATOR && echo "${COLOR_YELLOW}Failed systemd units${COLOR_RESET}" && echo $LINE_SEPARATOR
  systemctl --failed --no-pager || true

  for service in "${SERVICES_SYSTEMD[@]}"; do
    echo $LINE_SEPARATOR && echo "${COLOR_GREEN}Check logs for systemd service: $service${COLOR_RESET}" && echo $LINE_SEPARATOR
    journalctl -u "$service" -n 30 || true
  done

  dependency_logs

  local DOCSPACE_LOGS_DIR="/var/log/onlyoffice/docspace"
  local DOCUMENTSERVER_LOGS_DIR="/var/log/onlyoffice/documentserver"

  for LOGS_DIR in "${DOCSPACE_LOGS_DIR}" "${DOCUMENTSERVER_LOGS_DIR}"; do
    echo $LINE_SEPARATOR && echo "${COLOR_YELLOW}Check logs for $(basename "${LOGS_DIR}"| tr '[:lower:]' '[:upper:]') ${COLOR_RESET}" && echo $LINE_SEPARATOR

    [ -d "${LOGS_DIR}" ] || { echo "${COLOR_YELLOW}Logs directory ${LOGS_DIR} not found${COLOR_RESET}"; continue; }

    find "${LOGS_DIR}" -type f -name "*.log" ! -name "*sql*" ! -name "*nginx*" | while read -r FILE; do
      echo $LINE_SEPARATOR && echo "${COLOR_GREEN}Logs from file: ${FILE}${COLOR_RESET}" && echo $LINE_SEPARATOR
      tail -30 "${FILE}" || true
    done
  done
}

main() {
  get_colors
  
  case "${1:-logs}" in
    "healthcheck")
      echo "${COLOR_BLUE}${LINE_SEPARATOR}${COLOR_RESET}"
      echo "${COLOR_BLUE}HEALTH CHECK OF SYSTEMD SERVICES${COLOR_RESET}"
      echo "${COLOR_BLUE}${LINE_SEPARATOR}${COLOR_RESET}"
      healthcheck_systemd_services
      healthcheck_dead_systemd_services
      ;;
    "logs")
      echo "${COLOR_BLUE}${LINE_SEPARATOR}${COLOR_RESET}"
      echo "${COLOR_BLUE}COLLECTING SERVICE LOGS${COLOR_RESET}"
      echo "${COLOR_BLUE}${LINE_SEPARATOR}${COLOR_RESET}"
      services_logs
      ;;
    *)
      echo "Usage: $0 [healthcheck|logs]"
      exit 1
      ;;
  esac
}

main "$@"
