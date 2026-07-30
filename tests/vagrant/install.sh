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
    echo "${COLOR_RED} $(df -h) ${COLOR_RESET}"
}

add-repo-deb() {
  echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://nexus.onlyoffice.com/repository/4testing-debian stable main" | \
  sudo tee /etc/apt/sources.list.d/onlyoffice4testing.list
  curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | \
  gpg --batch --yes --dearmor -o /usr/share/keyrings/onlyoffice.gpg
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
      if [[ "${TEST_REPO_ENABLE}" == 'true' ]]; then
        add-repo-deb
      else
        rm -f /etc/apt/sources.list.d/onlyoffice4testing.list
      fi
      ;;

  centos|fedora|rhel)
      if [[ "${TEST_REPO_ENABLE}" == 'true' ]]; then
        add-repo-rpm
      else
        rm -f /etc/yum.repos.d/onlyoffice4testing.repo
      fi

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

  # Some RPM boxes ship firewalld enabled — it blocks the port forwarded to the host
  if command -v firewall-cmd >/dev/null 2>&1; then
    systemctl disable --now firewalld 2>/dev/null || true
  fi

  # Clean up home folder
  rm -rf /home/vagrant/*
  [ -d /tmp/docspace ] && mv /tmp/docspace/* /home/vagrant

  echo '127.0.0.1 host4test' | sudo tee -a /etc/hosts
  echo "${COLOR_GREEN}[OK] PREPARE_VM: Hostname was setting up${COLOR_RESET}"
}

install_docspace() {
  INSTALL_START_TIME=$(date +%s)
  [[ "${DOWNLOAD_SCRIPTS}" == 'true' ]] && curl -fsSLO https://download.onlyoffice.com/docspace/docspace-install.sh || sed 's/set -e/set -xe/' -i *.sh
  bash docspace-install.sh package ${ARGUMENTS} -log false || { echo "Exit code non-zero. Exit with 1."; exit 1; }
  echo "::notice::Installation on "${ID:-unknown} ${VERSION_ID:-}" took $((($(date +%s) - INSTALL_START_TIME) / 60))m"
}

main() {
  get_colors
  
  echo "${COLOR_BLUE}${LINE_SEPARATOR}${COLOR_RESET}"
  echo "${COLOR_BLUE}STEP 1: Preparing VM environment${COLOR_RESET}"
  echo "${COLOR_BLUE}${LINE_SEPARATOR}${COLOR_RESET}"
  prepare_vm
  
  echo "${COLOR_BLUE}${LINE_SEPARATOR}${COLOR_RESET}"
  echo "${COLOR_BLUE}STEP 2: Checking hardware${COLOR_RESET}"
  echo "${COLOR_BLUE}${LINE_SEPARATOR}${COLOR_RESET}"
  check_hw
  
  echo "${COLOR_BLUE}${LINE_SEPARATOR}${COLOR_RESET}"
  echo "${COLOR_BLUE}STEP 3: Installing${COLOR_RESET}"
  echo "${COLOR_BLUE}${LINE_SEPARATOR}${COLOR_RESET}"
  install_docspace
}

main
