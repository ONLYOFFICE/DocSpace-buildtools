#!/bin/bash

set -e

while [ "$1" != "" ]; do
	case $1 in
    -ds  | --download-scripts  ) [ -n "$2" ] && DOWNLOAD_SCRIPTS="$2"      && shift ;;
    -arg | --arguments         ) [ -n "$2" ] && ARGUMENTS="$2"             && shift ;;
    -tr  | --test-repo         ) [ -n "$2" ] && TEST_REPO_ENABLE="$2"      && shift ;;
  esac
  shift
done

export TERM=xterm-256color

get_colors() {
    export LINE_SEPARATOR="-----------------------------------------"
    export COLOR_BLUE=$'\e[34m' COLOR_GREEN=$'\e[32m' COLOR_RED=$'\e[31m' COLOR_RESET=$'\e[0m' COLOR_YELLOW=$'\e[33m'
}

check_hw() {
    echo "${COLOR_RED} $(free -h) ${COLOR_RESET}"
    echo "${COLOR_RED} $(nproc) ${COLOR_RESET}"
}

add-repo-deb() {
  mkdir -p "$HOME"/.gnupg && chmod 700 "$HOME"/.gnupg
  echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://nexus.onlyoffice.com/repository/4testing-debian stable main" | \
  sudo tee /etc/apt/sources.list.d/onlyoffice4testing.list
  curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | \
  gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/onlyoffice.gpg --import
  chmod 644 /usr/share/keyrings/onlyoffice.gpg
}

add-repo-rpm() {
  cat > /etc/yum.repos.d/onlyoffice4testing.repo <<END
[onlyoffice4testing]
name=onlyoffice4testing repo
baseurl=https://nexus.onlyoffice.com/repository/centos-testing/4testing/main/noarch
gpgcheck=1
enabled=1
gpgkey=https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE
END
}

prepare_vm() {
  # Ensure curl and gpg are installed
  if ! command -v curl >/dev/null 2>&1; then
    (command -v apt-get >/dev/null 2>&1 && apt-get update -y && apt-get install -y curl) || (command -v dnf >/dev/null 2>&1 && dnf install -y curl)
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    (command -v apt-get >/dev/null 2>&1 && apt-get update -y && apt-get install -y gnupg) || (command -v dnf >/dev/null 2>&1 && dnf install -y gnupg2)
  fi

  if [ -f /etc/os-release ]; then
    source /etc/os-release
case $ID in
  ubuntu|debian)
      [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-deb
      ;;

  centos|fedora|rhel)
      [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-rpm

      if [ "$ID" = "rhel" ] && [ "${VERSION_ID%%.*}" = "9" ]; then
          cat <<'EOF' | sudo tee /etc/yum.repos.d/centos-stream-9.repo
[centos9s-baseos]
name=CentOS Stream 9 - BaseOS
baseurl=http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/
enabled=1
gpgcheck=0

[centos9s-appstream]
name=CentOS Stream 9 - AppStream
baseurl=http://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/
enabled=1
gpgcheck=0
EOF
      fi
      ;;

  *)
      echo "${COLOR_RED}Failed to determine Linux dist${COLOR_RESET}"; exit 1
      ;;
esac

    if [[ "$ID" == "debian" ]]; then
      if dpkg -s postfix &>/dev/null; then
        apt-get remove -y postfix && echo "${COLOR_GREEN}[OK] PREPARE_VM: Postfix was removed${COLOR_RESET}"
      fi
    fi
  else
      echo "${COLOR_RED}File /etc/os-release doesn't exist${COLOR_RESET}"; exit 1
  fi

  # Clean up home folder
  rm -rf /home/vagrant/*
  [ -d /tmp/docspace ] && mv /tmp/docspace/* /home/vagrant

  echo '127.0.0.1 host4test' | sudo tee -a /etc/hosts
  echo "${COLOR_GREEN}[OK] PREPARE_VM: Hostname was setting up${COLOR_RESET}"
}

install_docspace() {
  [[ "${DOWNLOAD_SCRIPTS}" == 'true' ]] && curl -fsSLO https://download.onlyoffice.com/docspace/docspace-install.sh || sed 's/set -e/set -xe/' -i *.sh
  bash docspace-install.sh package ${ARGUMENTS} -log false || { echo "Exit code non-zero. Exit with 1."; exit 1; }
  echo "Exit code 0. Continue..."
}

ports_audit() {
  echo -e "$LINE_SEPARATOR\n${COLOR_YELLOW}Listening ports (non-local = EXPOSED)${COLOR_RESET}\n$LINE_SEPARATOR"
  ss -lntupH | awk -v red="${COLOR_RED}" -v green="${COLOR_GREEN}" -v reset="${COLOR_RESET}" '
  function pname(s){ if (match(s,/"[^"]+"/)) return substr(s,RSTART+1,RLENGTH-2); else return s }
  function pidv(s){ if (match(s,/pid=[0-9]+/)) return substr(s,RSTART+4,RLENGTH-4); else return "-" }
  function is_local(addr){ return (addr ~ /(^127\.|\[::1\]:|\[::ffff:127\.)/) }
  BEGIN { printf "%-4s %-22s %-7s %-22s %s\n","PROT","LOCAL","PID","PROC","SCOPE" }
  { scope = is_local($5) ? green "LOCAL" reset : red "EXPOSED" reset;
    printf "%-4s %-22s %-7s %-22s %s\n", $1, $5, pidv($7), pname($7), scope }'
}

healthcheck_systemd_services() {
  echo -e "$LINE_SEPARATOR\n${COLOR_YELLOW}Systemd services health${COLOR_RESET}\n$LINE_SEPARATOR"
  for service in "${SERVICES_SYSTEMD[@]}"; do
    [[ "$service" == *migration* ]] && continue;
    if systemctl is-active --quiet "${service}"; then
      echo "${COLOR_GREEN}[OK] Service ${service} is running${COLOR_RESET}"
    else
      echo "${COLOR_RED}[FAILED] Service ${service} is not running${COLOR_RESET}"
      echo "::error::Service ${service} is not running"
      SYSTEMD_SVC_FAILED="true"
    fi
  done
  if [ -n "${SYSTEMD_SVC_FAILED}" ]; then
    exit 1
  fi
}

services_logs() {
  mapfile -t SERVICES_SYSTEMD < <(awk '/SERVICE_NAME=\(/{flag=1; next} /\)/{flag=0} flag' "build.sh" | sed -E 's/^[[:space:]]*|[[:space:]]*$//g; s/^/docspace-/; s/$/.service/')
  SERVICES_SYSTEMD+=("ds-converter.service" "ds-docservice.service" "ds-metrics.service")

  for service in "${SERVICES_SYSTEMD[@]}"; do
    echo $LINE_SEPARATOR && echo "${COLOR_GREEN}Check logs for systemd service: $service${COLOR_RESET}" && echo $LINE_SEPARATOR
    journalctl -u "$service" -n 30 || true
  done

  local DOCSPACE_LOGS_DIR="/var/log/onlyoffice/docspace"
  local DOCUMENTSERVER_LOGS_DIR="/var/log/onlyoffice/documentserver"

  for LOGS_DIR in "${DOCSPACE_LOGS_DIR}" "${DOCUMENTSERVER_LOGS_DIR}"; do
    echo $LINE_SEPARATOR && echo "${COLOR_YELLOW}Check logs for $(basename "${LOGS_DIR}"| tr '[:lower:]' '[:upper:]') ${COLOR_RESET}" && echo $LINE_SEPARATOR

    find "${LOGS_DIR}" -type f -name "*.log" ! -name "*sql*" ! -name "*nginx*" | while read -r FILE; do
      echo $LINE_SEPARATOR && echo "${COLOR_GREEN}Logs from file: ${FILE}${COLOR_RESET}" && echo $LINE_SEPARATOR
      tail -30 "${FILE}" || true
    done
  done
}

debug_exposed_ports() {
  echo -e "$LINE_SEPARATOR\n${COLOR_YELLOW}Debug: why ports are EXPOSED${COLOR_RESET}\n$LINE_SEPARATOR"

  local tmp="/tmp/exposed_ports.$$"
  ss -lntupH | awk '
    function is_local(addr){
      return (addr ~ /(^127\.|^\[::1\]:|^\[::ffff:127\.)/)
    }
    function pidv(s){
      if (match(s,/pid=[0-9]+/)) return substr(s,RSTART+4,RLENGTH-4);
      return ""
    }
    function pname(s){
      if (match(s,/"[^"]+"/)) return substr(s,RSTART+1,RLENGTH-2);
      return s
    }
    {
      # $5 = local addr:port, $7 = users:(("proc",pid=...))
      if (!is_local($5)) {
        p=pidv($7);
        if (p != "") {
          printf "%s\t%s\t%s\t%s\n", $1, $5, p, pname($7);
        }
      }
    }' | sort -u > "$tmp"

  if [[ ! -s "$tmp" ]]; then
    echo "${COLOR_GREEN}[OK] No EXPOSED sockets with pid found${COLOR_RESET}"
    rm -f "$tmp"
    return 0
  fi

  echo -e "${COLOR_YELLOW}PROT\tLOCAL\tPID\tPROC${COLOR_RESET}"
  cat "$tmp"

  echo
  while IFS=$'\t' read -r proto laddr pid proc; do
    echo "$LINE_SEPARATOR"
    echo "${COLOR_BLUE}PID ${pid} (${proc}) listens on ${laddr} (${proto})${COLOR_RESET}"

    local unit=""
    unit="$(systemctl status "${pid}" 2>/dev/null | awk -F': ' '/Loaded:/{next} /CGroup:/{next} /^●/{next} /Main PID:/{next} { } END{ }' >/dev/null; true)"
    unit="$(systemctl status "${pid}" 2>/dev/null | awk 'NR==1{gsub(/^● /,""); split($0,a," "); print a[1]}' || true)"
    if [[ -z "$unit" || "$unit" == "${pid}" ]]; then
      unit="$(grep -aoE '[^/]+\.service' /proc/"$pid"/cgroup 2>/dev/null | head -n1 || true)"
    fi

    if [[ -n "$unit" ]]; then
      echo "${COLOR_GREEN}Unit:${COLOR_RESET} $unit"
    else
      echo "${COLOR_RED}Unit:${COLOR_RESET} (not detected)"
    fi

    echo "${COLOR_GREEN}cmdline:${COLOR_RESET}"
    tr '\0' ' ' < /proc/"$pid"/cmdline 2>/dev/null; echo

    echo "${COLOR_GREEN}env (filtered):${COLOR_RESET}"
    tr '\0' '\n' < /proc/"$pid"/environ 2>/dev/null | \
      egrep -i '^(SERVER_|MANAGEMENT_|SPRING_|HOST(NAME)?=|PORT=|JAVA_TOOL_OPTIONS=|JDK_JAVA_OPTIONS=|_JAVA_OPTIONS=|JMX|RMI)' || true

    if [[ "$proc" == "java" ]] && command -v jcmd >/dev/null 2>&1; then
      echo "${COLOR_GREEN}jcmd VM.system_properties (filtered):${COLOR_RESET}"
      sudo jcmd "$pid" VM.system_properties 2>/dev/null | \
        egrep -i '(^| )(server\.address|server\.port|management\.server\.address|management\.server\.port|jmx|rmi|java\.rmi|com\.sun\.management\.jmxremote)' || true
    fi

    if [[ -n "$unit" ]]; then
      echo "${COLOR_GREEN}systemd [Service] section:${COLOR_RESET}"
      systemctl cat "$unit" 2>/dev/null | awk '
        /^\[Service\]/{flag=1}
        flag{print}
        flag && /^\[/{ if($0!="[Service]") exit }
      ' || true
    fi

  done < "$tmp"

  rm -f "$tmp"
}

main() {
  get_colors
  prepare_vm
  check_hw
  install_docspace
  sleep 180
  services_logs
  ports_audit
  debug_exposed_ports
  healthcheck_systemd_services
}

main
