#!/bin/bash

set -e

while [ "$1" != "" ]; do
    case $1 in
      -ds | --download-scripts )
        if [ "$2" != "" ]; then
          DOWNLOAD_SCRIPTS=$2
          shift
        fi
      ;;

      -arg | --arguments )
          if [ "$2" != "" ]; then
            ARGUMENTS=$2
            shift
          fi
      ;;

      -li | --local-install )
          if [ "$2" != "" ]; then
            LOCAL_INSTALL=$2
            shift
          fi
      ;;

      -tr | --test-repo )
          if [ "$2" != "" ]; then
            TEST_REPO_ENABLE=$2
            shift
          fi
      ;;
    esac
    shift
done

export TERM=xterm-256color^M

function common::get_colors() {
    export LINE_SEPARATOR="-----------------------------------------"
    export COLOR_BLUE=$'\e[34m' COLOR_GREEN=$'\e[32m' COLOR_RED=$'\e[31m' COLOR_RESET=$'\e[0m' COLOR_YELLOW=$'\e[33m'
}

#############################################################################################
# Checking available resources for a virtual machine
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
#############################################################################################
function check_hw() {
    echo "${COLOR_RED} $(free -h) ${COLOR_RESET}"
    echo "${COLOR_RED} $(nproc) ${COLOR_RESET}"
}

#############################################################################################
# Add nexus repositories for test packages for .deb and .rpm packages 
# Globals:     None
# Arguments:   None
# Outputs:     None
#############################################################################################
function add-repo-deb() {
  mkdir -p -m 700 $HOME/.gnupg
  echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://nexus.onlyoffice.com/repository/4testing-debian stable main" | \
  sudo tee /etc/apt/sources.list.d/onlyoffice4testing.list
  curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | \
  gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/onlyoffice.gpg --import
  chmod 644 /usr/share/keyrings/onlyoffice.gpg
}

function add-repo-rpm() {
  cat > /etc/yum.repos.d/onlyoffice4testing.repo <<END
[onlyoffice4testing]
name=onlyoffice4testing repo
baseurl=https://nexus.onlyoffice.com/repository/centos-testing/4testing/main/noarch
gpgcheck=1
enabled=1
gpgkey=https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE
END
}

#############################################################################################
# Prepare vagrant boxes like: set hostname/remove postfix for DEB distributions
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   ☑ PREPAVE_VM: **<prepare_message>**
#############################################################################################
function prepare_vm() {
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    case $ID in
      ubuntu)
          [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-deb
          ;;

      debian)
          [ "$VERSION_CODENAME" == "bookworm" ] && apt-get update -y && apt install -y curl gnupg
          apt-get remove postfix -y && echo "${COLOR_GREEN}☑ PREPAVE_VM: Postfix was removed${COLOR_RESET}"
          [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-deb
          ;;

      fedora)
          [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-rpm
          ;;

      centos)
          [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-rpm
          yum -y install centos*-release 
          ;;

      *)
          echo "${COLOR_RED}Failed to determine Linux dist${COLOR_RESET}"; exit 1
          ;;
    esac
  else
      echo "${COLOR_RED}File /etc/os-release doesn't exist${COLOR_RESET}"; exit 1
  fi

  # Clean up home folder
  rm -rf /home/vagrant/*
  [ -d /tmp/docspace ] && mv /tmp/docspace/* /home/vagrant

  echo '127.0.0.1 host4test' | sudo tee -a /etc/hosts   
  echo "${COLOR_GREEN}☑ PREPAVE_VM: Hostname was setting up${COLOR_RESET}"   
}

#############################################################################################
# Install docspace and then healthcheck
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Script log
#############################################################################################
function install_docspace() {
  [[ "${DOWNLOAD_SCRIPTS}" == 'true' ]] && wget https://download.onlyoffice.com/docspace/docspace-install.sh || sed 's/set -e/set -xe/' -i *.sh
  bash docspace-install.sh package ${ARGUMENTS} || { echo "Exit code non-zero. Exit with 1."; exit 1; }
  echo "Exit code 0. Continue..."
}

#############################################################################################
# Healthcheck function for systemd services
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Message about service status 
#############################################################################################
function healthcheck_systemd_services() {
  for service in ${SERVICES_SYSTEMD[@]}; do
    [[ "$service" == "docspace-migration-runner.service" ]] && continue;
    if systemctl is-active --quiet ${service}; then
      echo "${COLOR_GREEN}☑ OK: Service ${service} is running${COLOR_RESET}"
    else
      echo "${COLOR_RED}⚠ FAILED: Service ${service} is not running${COLOR_RESET}"
      SYSTEMD_SVC_FAILED="true"
    fi
  done
}

#############################################################################################
# Set output if some services failed
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   ⚠ ⚠  ATTENTION: Some sevices is not running ⚠ ⚠ 
# Returns
# 0 if all services is start correctly, non-zero if some failed
#############################################################################################
function healthcheck_general_status() {
  if [ ! -z "${SYSTEMD_SVC_FAILED}" ]; then
    echo "${COLOR_YELLOW}⚠ ⚠  ATTENTION: Some sevices is not running ⚠ ⚠ ${COLOR_RESET}"
    exit 1
  fi
}

#############################################################################################
# Get logs for all services
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Logs for systemd services
# Returns:
#   none
# Commentaries:
# This function succeeds even if the file for cat was not found. For that use ${SKIP_EXIT} variable
#############################################################################################
function services_logs() {
  SERVICES_SYSTEMD=($(awk '/SERVICE_NAME=\(/{flag=1; next} /\)/{flag=0} flag' "build.sh" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^/docspace-/' | sed 's/$/.service/'))
  SERVICES_SYSTEMD+=("ds-converter.service" "ds-docservice.service" "ds-metrics.service")

  for service in ${SERVICES_SYSTEMD[@]}; do
    echo $LINE_SEPARATOR && echo "${COLOR_GREEN}Check logs for systemd service: $service${COLOR_RESET}" && echo $LINE_SEPARATOR   
    journalctl -u $service -n 30 || true
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

main() {
  common::get_colors
  prepare_vm
  check_hw
  install_docspace
  sleep 120
  services_logs
  healthcheck_systemd_services
  healthcheck_general_status
}

main
