#!/bin/bash

set -ex

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


	        -pi | --production-install )
			if [ "$2" != "" ]; then
				PRODUCTION_INSTALL=$2
				shift
			fi
		;;

		-li | --local-install )
                        if [ "$2" != "" ]; then
                                LOCAL_INSTALL=$2
                                shift
                        fi
                ;;

		-lu | --local-update )
                        if [ "$2" != "" ]; then
                                LOCAL_UPDATE=$2
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

SERVICES_SYSTEMD=(
        "docspace-api.service"
        "docspace-doceditor.service"
        "docspace-studio-notify.service"
        "docspace-files.service"
        "docspace-notify.service"
        "docspace-studio.service"
        "docspace-backup-background.service"
        "docspace-files-services.service"
        "docspace-people-server.service"
        "docspace-backup.service"
        "docspace-healthchecks.service"
        "docspace-socket.service"
        "docspace-clear-events.service"
        "docspace-login.service"
        "docspace-ssoauth.service"
        "ds-converter.service"
        "ds-docservice.service"
        "ds-metrics.service")      

function common::get_colors() {
    COLOR_BLUE=$'\e[34m'
    COLOR_GREEN=$'\e[32m'
    COLOR_RED=$'\e[31m'
    COLOR_RESET=$'\e[0m'
    COLOR_YELLOW=$'\e[33m'
    export COLOR_BLUE
    export COLOR_GREEN
    export COLOR_RED
    export COLOR_RESET
    export COLOR_YELLOW
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
        local FREE_RAM=$(free -h)
	local FREE_CPU=$(nproc)
	echo "${COLOR_RED} ${FREE_RAM} ${COLOR_RESET}"
        echo "${COLOR_RED} ${FREE_CPU} ${COLOR_RESET}"
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
          if [ "$VERSION_CODENAME" == "bookworm" ]; then
            apt-get update -y
            apt install -y curl gnupg
          fi
          apt-get remove postfix -y
          echo "${COLOR_GREEN}☑ PREPAVE_VM: Postfix was removed${COLOR_RESET}"
          [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-deb
          ;;

      fedora)
          [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-rpm
          ;;

      centos)
          if [ "$VERSION_ID" == "9" ]; then
            update-crypto-policies --set LEGACY
            echo "${COLOR_GREEN}☑ PREPAVE_VM: sha1 gpg key chek enabled${COLOR_RESET}"
          fi
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

  if [ -d /tmp/docspace ]; then
      mv /tmp/docspace/* /home/vagrant
  fi

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
	if [ "${DOWNLOAD_SCRIPTS}" == 'true' ]; then
            wget https://download.onlyoffice.com/docspace/docspace-install.sh
  else
    sed 's/set -e/set -xe/' -i *.sh
  fi

	printf "N\nY\nY" | bash docspace-install.sh ${ARGUMENTS} -log false

	if [[ $? != 0 ]]; then
	    echo "Exit code non-zero. Exit with 1."
	    exit 1
	else
	    echo "Exit code 0. Continue..."
	fi
}

#############################################################################################
# Healthcheck function for systemd services
# Globals:
#   SERVICES_SYSTEMD
# Arguments:
#   None
# Outputs:
#   Message about service status 
#############################################################################################
function healthcheck_systemd_services() {
  for service in ${SERVICES_SYSTEMD[@]} 
  do
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
#   $SERVICES_SYSTEMD
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
  for service in ${SERVICES_SYSTEMD[@]}; do
    echo -----------------------------------------
    echo "${COLOR_GREEN}Check logs for systemd service: $service${COLOR_RESET}"
    echo ---------------------- -------------------
    EXIT_CODE=0
    journalctl -u $service || true
  done
  
  local MAIN_LOGS_DIR="/var/log/onlyoffice"
  local DOCSPACE_LOGS_DIR="${MAIN_LOGS_DIR}/docspace"
  local DOCUMENTSERVER_LOGS_DIR="${MAIN_LOGS_DIR}/documentserver"
  local DOCSERVICE_LOGS_DIR="${DOCUMENTSERVER_LOGS_DIR}/docservice"
  local CONVERTER_LOGS_DIR="${DOCUMENTSERVER_LOGS_DIR}/converter"
  local METRICS_LOGS_DIR="${DOCUMENTSERVER_LOGS_DIR}/metrics"
       
  ARRAY_MAIN_SERVICES_LOGS=($(ls ${MAIN_LOGS_DIR} | grep log | sed 's/web.sql.log//;s/web.api.log//;s/nginx.*//' ))
  ARRAY_DOCSPACE_LOGS=($(ls ${DOCSPACE_LOGS_DIR}))
  ARRAY_DOCSERVICE_LOGS=($(ls ${DOCSERVICE_LOGS_DIR}))
  ARRAY_CONVERTER_LOGS=($(ls ${CONVERTER_LOGS_DIR}))
  ARRAY_METRICS_LOGS=($(ls ${METRICS_LOGS_DIR}))
  
  echo             "-----------------------------------"
  echo "${COLOR_YELLOW} Check logs for main services ${COLOR_RESET}"
  echo             "-----------------------------------"
  for file in ${ARRAY_MAIN_SERVICES_LOGS[@]}; do
    echo ---------------------------------------
    echo "${COLOR_GREEN}logs from file: ${file}${COLOR_RESET}"
    echo ---------------------------------------
    cat ${MAIN_LOGS_DIR}/${file} || true
  done
  
  echo             "-----------------------------------"
  echo "${COLOR_YELLOW} Check logs for Docservice ${COLOR_RESET}"
  echo             "-----------------------------------"
  for file in ${ARRAY_DOCSERVICE_LOGS[@]}; do
    echo ---------------------------------------
    echo "${COLOR_GREEN}logs from file: ${file}${COLOR_RESET}"
    echo ---------------------------------------
    cat ${DOCSERVICE_LOGS_DIR}/${file} || true
  done
  
  echo             "-----------------------------------"
  echo "${COLOR_YELLOW} Check logs for Converter ${COLOR_RESET}"
  echo             "-----------------------------------"
  for file in ${ARRAY_CONVERTER_LOGS[@]}; do
    echo ---------------------------------------
    echo "${COLOR_GREEN}logs from file ${file}${COLOR_RESET}"
    echo ---------------------------------------
    cat ${CONVERTER_LOGS_DIR}/${file} || true
  done
  
  echo             "-----------------------------------"
  echo "${COLOR_YELLOW} Start logs for Metrics ${COLOR_RESET}"
  echo             "-----------------------------------"
  for file in ${ARRAY_METRICS_LOGS[@]}; do
    echo ---------------------------------------
    echo "${COLOR_GREEN}logs from file ${file}${COLOR_RESET}"
    echo ---------------------------------------
    cat ${METRICS_LOGS_DIR}/${file} || true
  done

  echo             "-----------------------------------"
  echo "${COLOR_YELLOW} Start logs for DocSpace ${COLOR_RESET}"
  echo             "-----------------------------------"
  for file in ${ARRAY_DOCSPACE_LOGS[@]}; do
    echo ---------------------------------------
    echo "${COLOR_GREEN}logs from file ${file}${COLOR_RESET}"
    echo ---------------------------------------
    cat ${DOCSPACE_LOGS_DIR}/${file} || true
  done
}

function healthcheck_docker_installation() {
	exit 0
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
