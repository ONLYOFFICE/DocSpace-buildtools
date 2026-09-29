#!/bin/bash

 #
 # Copyright (C) Ascensio System SIA, 2009-2026
 #
 # This program is a free software product. You can redistribute it and/or
 # modify it under the terms of the GNU Affero General Public License (AGPL)
 # version 3 as published by the Free Software Foundation, together with the
 # additional terms provided in the LICENSE file.
 #
 # This program is distributed WITHOUT ANY WARRANTY; without even the implied
 # warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. For
 # details, see the GNU AGPL at: https://www.gnu.org/licenses/agpl-3.0.html
 #
 # You can contact Ascensio System SIA by email at info@onlyoffice.com
 # or by postal mail at 20A-6 Ernesta Birznieka-Upisha Street, Riga,
 # LV-1050, Latvia, European Union.
 #
 # The interactive user interfaces in modified versions of the Program
 # are required to display Appropriate Legal Notices in accordance with
 # Section 5 of the GNU AGPL version 3.
 #
 # No trademark rights are granted under this License.
 #
 # All non-code elements of the Product, including illustrations,
 # icon sets, and technical writing content, are licensed under the
 # Creative Commons Attribution-ShareAlike 4.0 International License:
 # https://creativecommons.org/licenses/by-sa/4.0/legalcode
 #
 # This license applies only to such non-code elements and does not
 # modify or replace the licensing terms applicable to the Program's
 # source code, which remains licensed under the GNU Affero General
 # Public License v3.
 #
 # SPDX-License-Identifier: AGPL-3.0-only
 #

PACKAGE_SYSNAME="onlyoffice"
PRODUCT="apps"
LEGACY_PRODUCT="docspace"
PRODUCT_NAME="${PACKAGE_SYSNAME^^} Apps"
BASE_DIR="/app/$PACKAGE_SYSNAME"
STATUS=""
DOCKER_TAG=""
INSTALLATION_TYPE="enterprise"
IDENTITY_CONTAINER_NAME="${PACKAGE_SYSNAME}-identity-api"

NETWORK_NAME=${PACKAGE_SYSNAME}

SWAPFILE="/${PRODUCT}_swapfile"
MAKESWAP="true"

DISK_REQUIREMENTS=40960
MEMORY_REQUIREMENTS=8000
CORE_REQUIREMENTS=4

DIST=""
REV=""
KERNEL=""

INSTALL_REDIS="true"
INSTALL_RABBITMQ="true"
INSTALL_MYSQL_SERVER="true"
INSTALL_DOCUMENT_SERVER="true"
INSTALL_ELASTICSEARCH="true"
INSTALL_FLUENT_BIT="true"
INSTALL_PRODUCT="true"
UNINSTALL="false"
USERNAME=""
PASSWORD=""

MYSQL_VERSION=""
MYSQL_DATABASE=""
MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_ROOT_PASSWORD=""
MYSQL_HOST=""
MYSQL_PORT=""
DATABASE_MIGRATION="true"

ELK_VERSION=""
ELK_SCHEME=""
ELK_HOST=""
ELK_PORT=""

REDIS_HOST=""
REDIS_PORT=""
REDIS_USER_NAME=""
REDIS_PASSWORD=""

RABBIT_PROTOCOL=""
RABBIT_HOST=""
RABBIT_PORT=""
RABBIT_USER_NAME=""
RABBIT_PASSWORD=""

DOCUMENT_SERVER_IMAGE_NAME=""
DOCUMENT_SERVER_VERSION=""
DOCUMENT_SERVER_JWT_SECRET=""
DOCUMENT_SERVER_JWT_HEADER=""
DOCUMENT_SERVER_URL_EXTERNAL=""

APP_CORE_BASE_DOMAIN=""
APP_CORE_MACHINEKEY=""
ENV_EXTENSION=""
LETS_ENCRYPT_DOMAIN=""
LETS_ENCRYPT_MAIL=""
IDENTITY_ENCRYPTION_SECRET=""

DEPLOYMENT_MODE=""
NON_INTERACTIVE="false"
SKIP_HARDWARE_CHECK="false"

EXTERNAL_PORT="80"
EXTERNAL_PORT_HTTPS="443"
ARGS_SCRIPT="install-Docker-args.sh"
DOWNLOAD_URL_PREFIX="https://download.${PACKAGE_SYSNAME}.com/${PRODUCT}"
GIT_BRANCH=$(echo "$@" | grep -oP '(?<=-gb )\S+' | tail -n 1)
LOCAL_SCRIPTS=$(echo "$@" | grep -oP '(?<=-ls |--localscripts )\S+' | tail -n 1)
OFFLINE_INSTALLATION="$(echo "$@" | grep -oP '(?<=-off |--offline )\S+' | tail -n 1)"
OFFLINE_INSTALLATION="${OFFLINE_INSTALLATION:-false}"

if [[ -n "${GIT_BRANCH:-}" ]]; then
  DOWNLOAD_URL_PREFIX="https://raw.githubusercontent.com/${PACKAGE_SYSNAME^^}/${LEGACY_PRODUCT}-buildtools/${GIT_BRANCH}/install/OneClickInstall"
fi

if [[ "$LOCAL_SCRIPTS" = "true" ]] || [[ "$OFFLINE_INSTALLATION" = "true" ]]; then
	source "./${ARGS_SCRIPT}"
else
	ARGS_SCRIPT_TMP="$(mktemp)"
	trap 'rm -f "${ARGS_SCRIPT_TMP:-}"' EXIT
	curl -fsSL --retry 3 --retry-delay 2 "${DOWNLOAD_URL_PREFIX}/${ARGS_SCRIPT}" -o "${ARGS_SCRIPT_TMP}" || { echo "Failed to download ${ARGS_SCRIPT}" >&2; exit 1; }
	bash -n "${ARGS_SCRIPT_TMP}" || { echo "Downloaded ${ARGS_SCRIPT} has invalid Bash syntax" >&2; exit 1; }
	source "${ARGS_SCRIPT_TMP}"
	rm -f "${ARGS_SCRIPT_TMP}"
fi

# Load the Docs lifecycle helpers for fresh installs, adoption and later updates.
DOCS_SCRIPT="install-Docker-docs.sh"
if [[ "$LOCAL_SCRIPTS" = "true" ]] || [[ "$OFFLINE_INSTALLATION" = "true" ]]; then
	source "$(dirname "${BASH_SOURCE[0]}")/${DOCS_SCRIPT}" || exit 1
else
	DOCS_SCRIPT_TMP="$(mktemp)" || exit 1
	if ! curl -fsSL --retry 3 --retry-delay 2 "${DOWNLOAD_URL_PREFIX}/${DOCS_SCRIPT}" -o "${DOCS_SCRIPT_TMP}"; then
		rm -f "${DOCS_SCRIPT_TMP}"
		echo "Failed to download ${DOCS_SCRIPT}" >&2
		exit 1
	fi
	if ! bash -n "${DOCS_SCRIPT_TMP}"; then
		rm -f "${DOCS_SCRIPT_TMP}"
		echo "Downloaded ${DOCS_SCRIPT} has invalid Bash syntax" >&2
		exit 1
	fi
	source "${DOCS_SCRIPT_TMP}"
	rm -f "${DOCS_SCRIPT_TMP}"
fi

select_deployment_mode () {
  case "${DEPLOYMENT_MODE}" in
    standalone)
      CONTAINER_NAME="${PACKAGE_SYSNAME}-${PRODUCT}"
      IMAGE_NAME="${PACKAGE_SYSNAME}/${STATUS}${PRODUCT}"
      SERVICES=("${PRODUCT}")
      COMPOSE_FILES=(-f "${BASE_DIR}/docker-compose.yml")
      ;;
    stack)
      CONTAINER_NAME="${PACKAGE_SYSNAME}-dotnet-services"
      IMAGE_NAME="${PACKAGE_SYSNAME}/${STATUS}${PRODUCT}-dotnet"
      SERVICES=("${PRODUCT}-stack" proxy)
      COMPOSE_FILES=()
      for SERVICE in "${SERVICES[@]}"; do
        COMPOSE_FILES+=(-f "${BASE_DIR}/${SERVICE}.yml")
      done
      ;;
    *)
      CONTAINER_NAME="${PACKAGE_SYSNAME}-api"
      IMAGE_NAME="${PACKAGE_SYSNAME}/${STATUS}${PRODUCT}-api"
      SERVICES=(migration-runner identity notify "${PRODUCT}" healthchecks proxy)
      COMPOSE_FILES=()
      for SERVICE in "${SERVICES[@]}"; do
        COMPOSE_FILES+=(-f "${BASE_DIR}/${SERVICE}.yml")
      done
      ;;
  esac
}

detect_current_deployment_mode () {
	is_command_exists docker || return 0

	if [ -n "$(docker ps -a -q -f "name=^${PACKAGE_SYSNAME}-${PRODUCT}$")" ]; then
		CURRENT_DEPLOYMENT_MODE="standalone"
	elif [ -n "$(docker ps -a -q -f "name=^${PACKAGE_SYSNAME}-dotnet-services$")" ]; then
		CURRENT_DEPLOYMENT_MODE="stack"
	elif [ -n "$(docker ps -a -q -f "name=^${PACKAGE_SYSNAME}-api$")" ]; then
		CURRENT_DEPLOYMENT_MODE="microservices"
	fi

	if [ -n "${CURRENT_DEPLOYMENT_MODE}" ] && [ "${DEPLOYMENT_MODE_SET}" != "true" ] && [ "${DEPLOYMENT_MODE}" != "${CURRENT_DEPLOYMENT_MODE}" ]; then
		DEPLOYMENT_MODE="${CURRENT_DEPLOYMENT_MODE}"
		select_deployment_mode
	fi
}

uninstall() {
    select_deployment_mode
    detect_current_deployment_mode

    DOCKER_COMPOSE="$(docker compose version >/dev/null 2>&1 && echo 'docker compose' || echo 'docker-compose')"

    if [ "${DEPLOYMENT_MODE}" = "standalone" ]; then
        echo "Uninstallation of ${PRODUCT_NAME} (standalone)..."

        read -p "Also remove data volumes (mysql, opensearch, documents)? (Y/n): " REMOVE_DATA_SERVICES
        DOWN_ARGS=(down)
        [[ "${REMOVE_DATA_SERVICES,,}" =~ ^(y|yes)?$ ]] && DOWN_ARGS+=(-v)
        compose_with_document_server_mounts "${COMPOSE_FILES[@]}" "${DOWN_ARGS[@]}" || echo "Failed to remove ${PRODUCT_NAME}."
    else
        read -p "Uninstall all dependencies (mysql, opensearch and others)? (Y/n): " REMOVE_DATA_SERVICES
        DOWN_ARGS=(down)

        if [[ "${REMOVE_DATA_SERVICES,,}" =~ ^(y|yes)?$ ]]; then
            SERVICES+=("db" "rabbitmq" "redis" "opensearch" "dashboards" "fluent")
            DOWN_ARGS+=(-v)
        fi

        for SERVICE in "${SERVICES[@]}" "ds"; do
            if [[ -f "$BASE_DIR/$SERVICE.yml" ]]; then
                echo "Uninstallation of $SERVICE..."
                compose_with_document_server_mounts -f "$BASE_DIR/$SERVICE.yml" "${DOWN_ARGS[@]}" || echo "Failed to remove $SERVICE."
            fi
        done
    fi

	docker network rm "${NETWORK_NAME}" 2>/dev/null || echo "Failed to remove network ${NETWORK_NAME}."

	read -p "Keep configuration and Docs data for reinstallation? (Y/n): " KEEP_DATA

	if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1 && [[ -d "$BASE_DIR" ]]; then
		if [[ ! "${KEEP_DATA,,}" =~ ^(y|yes)?$ ]]; then
			rm -rf "$BASE_DIR" || echo "Failed to remove directory $BASE_DIR."
		fi
	fi

	echo -e "Uninstallation of $PRODUCT_NAME" \
		"$( [[ "${REMOVE_DATA_SERVICES,,}" =~ ^(y|yes)?$ ]] && echo "and all dependencies" ) \e[32mcompleted.\e[0m"
}

root_checking () {
	PID=$$
	[[ $EUID -eq 0 ]] || { echo "To perform this action you must be logged in with root rights"; exit 1; }
}

is_command_exists () {
    type "$1" &> /dev/null
}

get_random_str () {
    local LENGTH=${1:-12}
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$LENGTH"
}

get_os_info () {
	OS="$(uname -s | tr '[:upper:]' '[:lower:]')"

    case "$OS" in
        windowsnt|darwin|sunos|aix)
            echo "Not supported OS"
            exit 1
            ;;
    esac

	if [ "$OS" == "linux" ]; then
		KERNEL=$(uname -r)

		if [ -f /etc/redhat-release ]; then
            if grep -qsw release /etc/redhat-release; then
                DIST=$(sed 's/ release.*//' /etc/redhat-release)
                REV=$(grep -oP '(?<=release )\d+' /etc/redhat-release)
            else
                DIST=$(grep -sw 'ID' /etc/os-release | cut -d= -f2 | tr -d '"')
                REV=$(grep -sw 'VERSION_ID' /etc/os-release | cut -d= -f2 | tr -d '"')
            fi
        elif [ -f /etc/SuSE-release ]; then
            DIST='SuSe'
            REV=$(grep '^VERSION_ID' /etc/os-release | cut -d= -f2 | tr -d '"')
        elif [ -f /etc/debian_version ]; then
            DIST='Debian'
            REV=$(cat /etc/debian_version)
            if [ -f /etc/lsb-release ]; then
                DIST=$(grep '^DISTRIB_ID' /etc/lsb-release | cut -d= -f2 | tr -d '"')
                REV=$(grep '^DISTRIB_RELEASE' /etc/lsb-release | cut -d= -f2 | tr -d '"')
            elif command -v lsb_release > /dev/null 2>&1; then
                DIST=$(lsb_release -si)
                REV=$(lsb_release -sr)
            fi
        elif [ -f /etc/VERSION ]; then
            DIST=$(grep -oP 'os_name="\K[^"]+' /etc/VERSION)
            REV=$(grep -oP 'majorversion="\K[^"]+' /etc/VERSION)
        elif [ -f /etc/os-release ]; then
            DIST=$(grep -sw 'ID' /etc/os-release | cut -d= -f2 | tr -d '"')
            REV=$(grep -sw 'VERSION_ID' /etc/os-release | cut -d= -f2 | tr -d '"')
        fi

        DIST=$(echo "$DIST" | xargs)
        REV=$(echo "$REV" | xargs)
    fi
}

check_os_info () {
	if [[ -z ${KERNEL} || -z ${DIST} || -z ${REV} ]]; then
		echo "$KERNEL, $DIST, $REV"
		echo "Not supported OS"
		exit 1
	fi
}

check_kernel () {
	MIN_NUM_ARR=(3 10 0)
	CUR_NUM_ARR=()

	CUR_STR_ARR=$(echo "$KERNEL" | grep -Po "[0-9]+\.[0-9]+\.[0-9]+" | tr "." " ")
	for CUR_STR_ITEM in $CUR_STR_ARR; do
		CUR_NUM_ARR+=("$CUR_STR_ITEM")
	done

	INDEX=0

	while [[ $INDEX -lt 3 ]]; do
		if [ ${CUR_NUM_ARR[INDEX]} -lt ${MIN_NUM_ARR[INDEX]} ]; then
			echo "Not supported OS Kernel"
			exit 1
		elif [ ${CUR_NUM_ARR[INDEX]} -gt ${MIN_NUM_ARR[INDEX]} ]; then
			INDEX=3
		fi
		(( INDEX++ ))
	done
}

check_hardware () {
	AVAILABLE_DISK_SPACE=$(df -Pm / | awk 'NR == 2 { print $4 }')
	TOTAL_MEMORY=$(free --mega | awk '/^Mem:/ { print $2 }')
	CPU_CORES_NUMBER=$(nproc)

	local requirements_not_met=""

	if (( AVAILABLE_DISK_SPACE < DISK_REQUIREMENTS )); then
		requirements_not_met="${requirements_not_met}\n  - at least ${DISK_REQUIREMENTS} MB of free disk space (available: ${AVAILABLE_DISK_SPACE} MB)"
	fi

	if (( TOTAL_MEMORY < MEMORY_REQUIREMENTS )); then
		requirements_not_met="${requirements_not_met}\n  - at least ${MEMORY_REQUIREMENTS} MB of RAM (available: ${TOTAL_MEMORY} MB)"
	fi

	if (( CPU_CORES_NUMBER < CORE_REQUIREMENTS )); then
		requirements_not_met="${requirements_not_met}\n  - a CPU with at least ${CORE_REQUIREMENTS} cores (available: ${CPU_CORES_NUMBER})"
	fi

	if [ -n "${requirements_not_met}" ]; then
		printf "Minimal requirements are not met, your system needs:%b\n\nTo skip this check, use the --skiphardwarecheck true parameter\n" "${requirements_not_met}"
		exit 1
	fi
}

install_package () {
	if ! is_command_exists $1; then
		local COMMAND_NAME=$1
		local PACKAGE_NAME=${2:-"$COMMAND_NAME"}
		local PACKAGE_NAME_APT=${PACKAGE_NAME%%|*}
		local PACKAGE_NAME_YUM=${PACKAGE_NAME##*|}

		if is_command_exists apt-get; then
			apt-get -y -q install ${PACKAGE_NAME_APT:-$PACKAGE_NAME}
		elif is_command_exists yum; then
			yum -y install ${PACKAGE_NAME_YUM:-$PACKAGE_NAME}
		fi

		is_command_exists $COMMAND_NAME || { echo "Command $COMMAND_NAME not found"; exit 1; }
	fi
}

install_docker_compose () {
	local COMPOSE_ASSET COMPOSE_URL COMPOSE_TMP COMPOSE_SHA_TMP

	COMPOSE_ASSET="docker-compose-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
	COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/${COMPOSE_ASSET}"
	COMPOSE_TMP="$(mktemp)"
	COMPOSE_SHA_TMP="$(mktemp)"

	curl -fsSL --retry 3 --retry-delay 2 "${COMPOSE_URL}" -o "${COMPOSE_TMP}" || { rm -f "${COMPOSE_TMP}" "${COMPOSE_SHA_TMP}"; return 1; }
	curl -fsSL --retry 3 --retry-delay 2 "${COMPOSE_URL}.sha256" -o "${COMPOSE_SHA_TMP}" || { rm -f "${COMPOSE_TMP}" "${COMPOSE_SHA_TMP}"; return 1; }
	awk '{print $1 "  '"${COMPOSE_TMP}"'"}' "${COMPOSE_SHA_TMP}" | sha256sum -c - || { rm -f "${COMPOSE_TMP}" "${COMPOSE_SHA_TMP}"; return 1; }
	install -m 755 "${COMPOSE_TMP}" /usr/bin/docker-compose
	rm -f "${COMPOSE_TMP}" "${COMPOSE_SHA_TMP}"
	DOCKER_COMPOSE="docker-compose"
}

check_ports () {
	RESERVED_PORTS=()
	ARRAY_PORTS=()
	USED_PORTS=""
	EXTERNAL_PORT_NUM=""
	EXTERNAL_PORT_HTTPS_NUM=""

	if [[ "${EXTERNAL_PORT}" =~ ^[0-9]+$ ]] && (( 10#$EXTERNAL_PORT >= 1 && 10#$EXTERNAL_PORT <= 65535 )); then
		EXTERNAL_PORT_NUM=$((10#$EXTERNAL_PORT))
		for RESERVED_PORT in "${RESERVED_PORTS[@]}"
		do
			if [ "$RESERVED_PORT" -eq "$EXTERNAL_PORT_NUM" ] ; then
				echo "External port $EXTERNAL_PORT is reserved. Select another port"
				exit 1
			fi
		done
	else
		echo "Invalid external port $EXTERNAL_PORT"
		exit 1
	fi

	if [[ "${EXTERNAL_PORT_HTTPS}" =~ ^[0-9]+$ ]] && (( 10#$EXTERNAL_PORT_HTTPS >= 1 && 10#$EXTERNAL_PORT_HTTPS <= 65535 )); then
		EXTERNAL_PORT_HTTPS_NUM=$((10#$EXTERNAL_PORT_HTTPS))
		for RESERVED_PORT in "${RESERVED_PORTS[@]}"
		do
			if [ "$RESERVED_PORT" -eq "$EXTERNAL_PORT_HTTPS_NUM" ] ; then
				echo "External HTTPS port $EXTERNAL_PORT_HTTPS is reserved. Select another port"
				exit 1
			fi
		done
	else
		echo "Invalid external HTTPS port $EXTERNAL_PORT_HTTPS"
		exit 1
	fi

	if [ "$INSTALL_PRODUCT" == "true" ]; then
		ARRAY_PORTS+=("$EXTERNAL_PORT_NUM")
		# Standalone always publishes HTTPS.
		if [[ -n "$CERTIFICATE_PATH" ]] || [[ -n "$LETS_ENCRYPT_DOMAIN" ]] || [ "${DEPLOYMENT_MODE}" = "standalone" ]; then
			ARRAY_PORTS+=("$EXTERNAL_PORT_HTTPS_NUM")
		fi
	fi

	for PORT in "${ARRAY_PORTS[@]}"
	do
		REGEXP=":$PORT$"
		CHECK_RESULT=$(netstat -lnt | awk '{print $4}' | { grep $REGEXP || true; })

		if [[ $CHECK_RESULT != "" ]]; then
			if [[ $USED_PORTS != "" ]]; then
				USED_PORTS="$USED_PORTS, $PORT"
			else
				USED_PORTS="$PORT"
			fi
		fi
	done

	if [[ $USED_PORTS != "" ]]; then
		echo "The following TCP Ports must be available: $USED_PORTS"
		exit 1
	fi
}

install_docker () {

	if [ "${DIST}" == "Ubuntu" ] || [ "${DIST}" == "Debian" ] || [[ "${DIST}" == CentOS* ]] || [ "${DIST}" == "Fedora" ] || [[ "${DIST}" == "Red Hat Enterprise Linux"* ]]; then

		TMP=$(mktemp); trap 'rm -f "${TMP}"' EXIT
		curl -fsSL https://get.docker.com -o "${TMP}" || { echo -e "\nFailed to download Docker install script.\n"; exit 1; }
		bash "${TMP}" || { echo -e "\nDocker installation failed.\n"; exit 1; }
		systemctl start docker
		systemctl enable docker

	elif [ "${DIST}" == "SuSe" ]; then

		echo ""
		echo "Your operating system does not allow Docker CE installation."
		echo "You can install Docker EE using the manual here - https://docs.docker.com/engine/installation/linux/suse/"
		echo ""
		exit 1

	elif [ "${DIST}" == "altlinux" ]; then

		apt-get -y install docker-io
		chkconfig docker on
		service docker start
		systemctl enable docker

	elif [ "${DIST}" == "DSM" ]; then

		synopkg install_from_server ContainerManager
		synopkg start ContainerManager

	else

		echo ""
		echo "Docker could not be installed automatically."
		echo "Please use this official instruction https://docs.docker.com/engine/installation/linux/other/ for its manual installation."
		echo ""
		exit 1

	fi

	if ! is_command_exists docker ; then
		echo "error while installing docker"
		exit 1
	fi
}

docker_login() {
    if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
        echo "$PASSWORD" | docker login "$REGISTRY_URL" --username "$USERNAME" --password-stdin || { echo "Docker authentication failed"; exit 1; }
    fi
}

create_network () {
	NETWORK_EXIST=$(docker network ls | awk '{print $2;}' | { grep -x ${NETWORK_NAME} || true; })

	if [[ -z ${NETWORK_EXIST} ]]; then
		docker network create --driver bridge ${NETWORK_NAME}
	fi
}

domain_check () {
	# Keep any domain detected from an existing Docs container.
	APP_DOMAIN_PORTAL=${APP_DOMAIN_PORTAL:-$(cut -d ',' -f 1 <<< "$LETS_ENCRYPT_DOMAIN")}
	APP_DOMAIN_PORTAL=${APP_DOMAIN_PORTAL:-${APP_URL_PORTAL:-$(get_env_parameter "APP_URL_PORTAL" "${PACKAGE_SYSNAME}-files" | awk -F[/:] '{if ($1 == "https") print $4; else print ""}')}}
	# Standalone's external HTTPS domain lives in SSL_DOMAIN.
	APP_DOMAIN_PORTAL=${APP_DOMAIN_PORTAL:-$(get_env_parameter "SSL_DOMAIN" "${PACKAGE_SYSNAME}-${PRODUCT}" | cut -d ',' -f 1)}
	APP_URL_PORTAL=${APP_DOMAIN_PORTAL:+http://${APP_DOMAIN_PORTAL}:${EXTERNAL_PORT}}
}

establish_conn() {
	echo -n "Trying to establish $3 connection... "

	exec {FD}<> /dev/tcp/${1}/${2} && { exec {FD}>&-; echo "OK"; } || { echo "FAILURE"; exit 1; }
}

get_env_parameter () {
	local PARAMETER_NAME=$1
	local CONTAINER_NAME=$2
	local CONTAINER_EXIST=""
	local VALUE=""

	if [[ -z ${PARAMETER_NAME} ]]; then
		echo "Empty parameter name"
		exit 1
	fi

	if is_command_exists docker ; then
		[ -n "$CONTAINER_NAME" ] && CONTAINER_EXIST=$(docker ps -aqf "name=$CONTAINER_NAME")

		if [[ -n ${CONTAINER_EXIST} ]]; then
			VALUE=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "${CONTAINER_NAME}" | awk -v key="${PARAMETER_NAME}" '{ eq=index($0,"="); name=substr($0,1,eq-1); gsub(/^[ \t]+|[ \t]+$/,"",name); if (eq && name == key) { print substr($0,eq+1); exit } }')
		fi
	fi

	if [ -z "${VALUE}" ] && [ -f "${BASE_DIR}/.env" ]; then
		VALUE=$(awk -v key="${PARAMETER_NAME}" '{ eq=index($0,"="); name=substr($0,1,eq-1); gsub(/^[ \t]+|[ \t]+$/,"",name); if (eq && name == key) { print substr($0,eq+1); exit } }' "${BASE_DIR}/.env" | tr -d '\r')
	fi

	printf '%s\n' "${VALUE//\"/}"
}

get_tag_from_registry () {
	if [[ -n ${REGISTRY_URL} ]]; then
		if [[ -n ${USERNAME} && -n ${PASSWORD} ]]; then
			CREDENTIALS=$(echo -n "$USERNAME:$PASSWORD" | base64)
		elif [[ -f "$HOME/.docker/config.json" ]]; then
			CREDENTIALS=$(jq -r --arg registry "${REGISTRY_URL}" '.auths | to_entries[] | select(.key | contains($registry)).value.auth // empty' "$HOME/.docker/config.json")
		fi

		AUTH_HEADER=${CREDENTIALS:+Authorization: Basic $CREDENTIALS}

		REGISTRY_TAGS_URL="${REGISTRY_URL%/}/v2/${1}/tags/list"
		JQ_FILTER='.tags | join("\n")'
	else
		if [[ -n ${USERNAME} && -n ${PASSWORD} ]]; then
			CREDENTIALS="{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}"
			TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d "$CREDENTIALS" https://hub.docker.com/v2/users/login/ | jq -r '.token')
			AUTH_HEADER="Authorization: JWT $TOKEN"
			sleep 1
		fi
		ARCH="$(uname -m | sed -E 's/^(x86_64|amd64)$/amd64/; s/^(aarch64|arm64)$/arm64/')"
		REGISTRY_TAGS_URL="https://hub.docker.com/v2/repositories/${1}/tags?page_size=100"
		JQ_FILTER='.results[] | select(.name | test("^(?!99\\.).*")) | select(.images[]?.architecture=="'"$ARCH"'") | .name // empty'
	fi

	mapfile -t TAGS_RESP < <(curl -s -H "${AUTH_HEADER}" -X GET "${REGISTRY_TAGS_URL}" | jq -r "${JQ_FILTER}" | grep -v -x "latest")
}

get_available_version () {
	[ "${OFFLINE_INSTALLATION}" = "false" ] && get_tag_from_registry ${1} || mapfile -t TAGS_RESP < <(docker images --format "{{.Tag}}" "${1}" | grep -v -x "latest")

	VERSION_REGEX='^[0-9]+\.[0-9]+(\.[0-9]+){0,2}$'
	[ ${#TAGS_RESP[@]} -eq 1 ] && LATEST_TAG="${TAGS_RESP[0]}" || \
		LATEST_TAG=$(printf "%s\n" "${TAGS_RESP[@]}" | grep -E "$([[ $GIT_BRANCH == "develop" && -n $STATUS ]] && echo '^develop\.[0-9]+$' || echo "$VERSION_REGEX")" | sort -V | tail -n 1)
	# Fallback for 4testing develop tags.
	LATEST_TAG=${LATEST_TAG:-${STATUS:+$(printf "%s\n" "${TAGS_RESP[@]}" | sort -V | tail -n 1)}}

	if [ ! -z "${LATEST_TAG}" ]; then
		echo "${LATEST_TAG}" | sed "s/\"//g"
	else
		if [ "${OFFLINE_INSTALLATION}" = "false" ]; then
			echo "Unable to retrieve tag from ${1} repository" >&2
		else
			echo "Error: The image '${1}' is not found in the local Docker registry." >&2
		fi
		kill -s TERM $PID
	fi
}

set_secrets () {
	APP_CORE_MACHINEKEY="${APP_CORE_MACHINEKEY:-$(get_env_parameter "APP_CORE_MACHINEKEY" "${CONTAINER_NAME}")}"
	[ "$UPDATE" != "true" ] && APP_CORE_MACHINEKEY="${APP_CORE_MACHINEKEY:-$(get_random_str 12)}"
	IDENTITY_ENCRYPTION_SECRET="${IDENTITY_ENCRYPTION_SECRET:-$(get_env_parameter "IDENTITY_ENCRYPTION_SECRET" "${IDENTITY_CONTAINER_NAME}")}"
	# (DS v3.1.0) Legacy update fallback for the encryption key.
	[ "${UPDATE}" = "true" ] && IDENTITY_ENCRYPTION_SECRET="${IDENTITY_ENCRYPTION_SECRET:-"secret"}"
	IDENTITY_ENCRYPTION_SECRET="${IDENTITY_ENCRYPTION_SECRET:-$(get_random_str 12)}"
}

set_mysql_params () {
	MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(get_env_parameter "MYSQL_PASSWORD" "${CONTAINER_NAME}")}"
	MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(get_random_str 20)}"

	MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(get_env_parameter "MYSQL_ROOT_PASSWORD" "${CONTAINER_NAME}")}"
	MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(get_random_str 20)}"

	MYSQL_DATABASE="${MYSQL_DATABASE:-$(get_env_parameter "MYSQL_DATABASE" "${CONTAINER_NAME}")}"
	MYSQL_USER="${MYSQL_USER:-$(get_env_parameter "MYSQL_USER" "${CONTAINER_NAME}")}"
	MYSQL_HOST="${MYSQL_HOST:-$(get_env_parameter "MYSQL_HOST" "${CONTAINER_NAME}")}"
	MYSQL_PORT="${MYSQL_PORT:-$(get_env_parameter "MYSQL_PORT" "${CONTAINER_NAME}")}"
}

set_apps_params() {
	REGISTRY=${REGISTRY:-$(get_env_parameter "REGISTRY")}

	ENV_EXTENSION=${ENV_EXTENSION:-$(get_env_parameter "ENV_EXTENSION" "${CONTAINER_NAME}")}
	VOLUMES_DIR=${VOLUMES_DIR:-$(get_env_parameter "VOLUMES_DIR")}
	APP_CORE_BASE_DOMAIN=${APP_CORE_BASE_DOMAIN:-$(get_env_parameter "APP_CORE_BASE_DOMAIN" "${CONTAINER_NAME}")}
	if [ "${EXTERNAL_PORT_SET}" != true ]; then
		EXTERNAL_PORT=$(get_env_parameter "EXTERNAL_PORT" "${CONTAINER_NAME}")
		EXTERNAL_PORT=${EXTERNAL_PORT:-80}
	fi
	if [ "${EXTERNAL_PORT_HTTPS_SET}" != true ]; then
		EXTERNAL_PORT_HTTPS=$(get_env_parameter "EXTERNAL_PORT_HTTPS" "${CONTAINER_NAME}")
		EXTERNAL_PORT_HTTPS=${EXTERNAL_PORT_HTTPS:-443}
	fi

	PREVIOUS_ELK_VERSION=$(get_env_parameter "ELK_VERSION")
	ELK_SCHEME=${ELK_SCHEME:-$(get_env_parameter "ELK_SCHEME" "${CONTAINER_NAME}")}
	# (DS v3.2.0) Legacy ELK_SHEME typo fallback.
	ELK_SCHEME=${ELK_SCHEME:-$(get_env_parameter "ELK_SHEME" "${CONTAINER_NAME}")}
	ELK_HOST=${ELK_HOST:-$(get_env_parameter "ELK_HOST" "${CONTAINER_NAME}")}
	ELK_PORT=${ELK_PORT:-$(get_env_parameter "ELK_PORT" "${CONTAINER_NAME}")}

	REDIS_HOST=${REDIS_HOST:-$(get_env_parameter "REDIS_HOST" "${CONTAINER_NAME}")}
	REDIS_PORT=${REDIS_PORT:-$(get_env_parameter "REDIS_PORT" "${CONTAINER_NAME}")}
	REDIS_USER_NAME=${REDIS_USER_NAME:-$(get_env_parameter "REDIS_USER_NAME" "${CONTAINER_NAME}")}
	REDIS_PASSWORD=${REDIS_PASSWORD:-$(get_env_parameter "REDIS_PASSWORD" "${CONTAINER_NAME}")}

	RABBIT_HOST=${RABBIT_HOST:-$(get_env_parameter "RABBIT_HOST" "${CONTAINER_NAME}")}
	RABBIT_PORT=${RABBIT_PORT:-$(get_env_parameter "RABBIT_PORT" "${CONTAINER_NAME}")}
	RABBIT_USER_NAME=${RABBIT_USER_NAME:-$(get_env_parameter "RABBIT_USER_NAME" "${CONTAINER_NAME}")}
	RABBIT_PASSWORD=${RABBIT_PASSWORD:-$(get_env_parameter "RABBIT_PASSWORD" "${CONTAINER_NAME}")}
	RABBIT_VIRTUAL_HOST=${RABBIT_VIRTUAL_HOST:-$(get_env_parameter "RABBIT_VIRTUAL_HOST" "${CONTAINER_NAME}")}
	
	DASHBOARDS_USERNAME=${DASHBOARDS_USERNAME:-$(get_env_parameter "DASHBOARDS_USERNAME" "${CONTAINER_NAME}")}
	DASHBOARDS_PASSWORD=${DASHBOARDS_PASSWORD:-$(get_env_parameter "DASHBOARDS_PASSWORD" "${CONTAINER_NAME}")}

	CERTIFICATE_PATH=${CERTIFICATE_PATH:-$(get_env_parameter "CERTIFICATE_PATH")}
	CERTIFICATE_KEY_PATH=${CERTIFICATE_KEY_PATH:-$(get_env_parameter "CERTIFICATE_KEY_PATH")}
	DHPARAM_PATH=${DHPARAM_PATH:-$(get_env_parameter "DHPARAM_PATH")}
	EXTRA_HOSTS=${EXTRA_HOSTS:-$(get_env_parameter "EXTRA_HOSTS")}
}

set_installation_type_data () {
	detect_current_deployment_mode
	is_command_exists docker && UPDATE=${UPDATE:-$(test -n "${CURRENT_DEPLOYMENT_MODE}" && echo true)}
	if [ -z "${DOCUMENT_SERVER_IMAGE_NAME}" ]; then
		DOCUMENT_SERVER_IMAGE_NAME="${PACKAGE_SYSNAME}/${STATUS}documentserver"
		case "${INSTALLATION_TYPE}" in
			"developer") DOCUMENT_SERVER_IMAGE_NAME+="-de" ;;
			"enterprise") DOCUMENT_SERVER_IMAGE_NAME+="-ee" ;;
		esac
	fi
}

download_files () {
	local DOCKER_TARBALL DOWNLOAD_URL STAGING_DIR ARCHIVE_FILE DOCS_FILE
	local TAR_ARGS=()

	case "${DEPLOYMENT_MODE}" in
		standalone) DOCKER_TARBALL="docker-standalone.tar.gz" ;;
		stack)      DOCKER_TARBALL="docker-stack.tar.gz" ;;
		*)          DOCKER_TARBALL="docker.tar.gz" ;;
	esac

	[ "${OFFLINE_INSTALLATION}" = "false" ] && echo -n "Downloading configuration files to ${BASE_DIR}..." || echo "Unzip ${DOCKER_TARBALL} to ${BASE_DIR}..."

	STAGING_DIR="$(mktemp -d)" || return 1
	ARCHIVE_FILE="${STAGING_DIR}/${DOCKER_TARBALL}"
	trap 'rm -rf "${STAGING_DIR}"; trap - RETURN' RETURN

	if [ "${OFFLINE_INSTALLATION}" = "false" ]; then
		if [ -z "${GIT_BRANCH}" ]; then
			DOWNLOAD_URL="https://download.${PACKAGE_SYSNAME}.com/${PRODUCT}/${DOCKER_TARBALL}"
		else
			DOWNLOAD_URL="https://codeload.github.com/${PACKAGE_SYSNAME}/${LEGACY_PRODUCT}-buildtools/tar.gz/${GIT_BRANCH}"
			if [ "${DEPLOYMENT_MODE}" = "standalone" ]; then
				TAR_ARGS=(--strip-components=4 --wildcards '*/install/docker/standalone/*')
			else
				TAR_ARGS=(--strip-components=3 --wildcards '*/install/docker/*')
			fi
		fi
		curl -fsSL --retry 3 --retry-delay 2 "${DOWNLOAD_URL}" -o "${ARCHIVE_FILE}" || { echo "FAIL"; echo "Error: failed to download ${DOWNLOAD_URL}" >&2; return 1; }
		tar -xzf "${ARCHIVE_FILE}" -C "${STAGING_DIR}" "${TAR_ARGS[@]}" || { echo "FAIL"; echo "Error: failed to unpack ${DOCKER_TARBALL}" >&2; return 1; }
	else
		if [ -f "$(dirname "$0")/${DOCKER_TARBALL}" ]; then
			tar -xf "$(dirname "$0")/${DOCKER_TARBALL}" -C "${STAGING_DIR}" || { echo "FAIL"; echo "Error: failed to unpack ${DOCKER_TARBALL}" >&2; return 1; }
		else
			echo "Error: ${DOCKER_TARBALL} not found in the same directory as the script."
			echo "You need to download the ${DOCKER_TARBALL} file from https://download.${PACKAGE_SYSNAME}.com/${PRODUCT}/${DOCKER_TARBALL}"
			exit 1
		fi
	fi

	if [ ! -f "${STAGING_DIR}/.env" ]; then
		echo "FAIL"
		echo "Error: ${DOCKER_TARBALL} does not contain .env" >&2
		return 1
	fi

	if [ "${DEPLOYMENT_MODE}" = "standalone" ]; then
		[ -f "${STAGING_DIR}/docker-compose.yml" ] || { echo "FAIL"; echo "Error: ${DOCKER_TARBALL} does not contain docker-compose.yml" >&2; return 1; }
	else
		[ -f "${STAGING_DIR}/apps.yml" ] || { echo "FAIL"; echo "Error: ${DOCKER_TARBALL} does not contain apps.yml" >&2; return 1; }
	fi

	mkdir -p "${BASE_DIR}" "${STAGING_DIR}/config" || return 1
	# Preserve only the adopted Docs settings; refresh all other config files.
	rm -f -- "${STAGING_DIR}/config/ds.env" "${STAGING_DIR}/config/ds-mounts.json" || return 1
	for DOCS_FILE in ds.env ds-mounts.json; do
		if [ -f "${BASE_DIR}/config/${DOCS_FILE}" ]; then
			cp -a -- "${BASE_DIR}/config/${DOCS_FILE}" "${STAGING_DIR}/config/" || return 1
		fi
	done
	# Retain the staged settings for recovery if cleanup or copying fails.
	trap 'echo "Error: configuration refresh failed; recovery files remain in ${STAGING_DIR}" >&2; trap - RETURN' RETURN
	# Keep inherited certs across updates and mode switches.
	find "${BASE_DIR:?}" -mindepth 1 -maxdepth 1 -not -name "DocumentServer" -not -name "certs" -exec rm -rf {} + || return 1
	cp -a "${STAGING_DIR}/." "${BASE_DIR}/" || return 1
	trap 'rm -rf "${STAGING_DIR}"; trap - RETURN' RETURN
	rm -f "${BASE_DIR:?}/${DOCKER_TARBALL}"
	chmod 600 "${BASE_DIR}/.env"

	echo "OK"
}

reconfigure () {
	local VARIABLE_NAME="$1"
	local VARIABLE_VALUE="$2"
	local ENV_FILE="${BASE_DIR}/.env"
	local ENV_TMP

	if [[ -n ${VARIABLE_VALUE} ]]; then
		[[ "${VARIABLE_NAME}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "Invalid .env variable name: ${VARIABLE_NAME}" >&2; exit 1; }
		[[ "${VARIABLE_VALUE}" != *$'\n'* && "${VARIABLE_VALUE}" != *$'\r'* ]] || { echo "Invalid multiline value for ${VARIABLE_NAME}" >&2; exit 1; }
		[ -f "${ENV_FILE}" ] || { echo "Missing ${ENV_FILE}" >&2; exit 1; }

		ENV_TMP="$(mktemp "${BASE_DIR}/.env.XXXXXX")"
		awk -v key="${VARIABLE_NAME}" -v value="${VARIABLE_VALUE}" \
			'{ eq=index($0,"="); name=substr($0,1,eq-1); indent=name; sub(/[^ \t].*$/,"",indent); gsub(/^[ \t]+|[ \t]+$/,"",name); if (!updated && eq && name == key) { print indent key "=" value; updated=1; next } print } END { if (!updated) print key "=" value }' \
			"${ENV_FILE}" > "${ENV_TMP}" && mv -f "${ENV_TMP}" "${ENV_FILE}"
	fi
}

opensearch_set_heap_size () {
	local TARGET_FILE="$1"
	local SAFE_MEMORY HEAP

	SAFE_MEMORY=$(( ( $(free --mega | grep -oP '\d+' | head -n 1) - 1024 ) / 2 ))
	HEAP=$(( SAFE_MEMORY < 2048 ? 1 : SAFE_MEMORY < 4096 ? 2 : 4 ))
	sed -i "s/Xms[0-9]g/Xms${HEAP}g/g; s/Xmx[0-9]g/Xmx${HEAP}g/g" "${TARGET_FILE}"
}

wait_mysql_healthy () {
	echo -n "Waiting for MySQL container to become healthy..."
	(timeout 30 bash -c "while ! docker inspect --format '{{json .State.Health.Status }}' ${PACKAGE_SYSNAME}-mysql-server | grep -q 'healthy'; do sleep 1; done") && echo "OK" || echo "FAILED"
}

# (DS v4.0.0) Docs UID varies; keep WOPI keys readable.
chown_excluding_wopi_keys () {
	find "$2" \( -name wopi_private.key -o -name wopi_public.key \) -prune -o -exec chown "$1" {} +
}

chown_app_volumes () {
	# (DS v3.8.0) Ensure app volumes are owned by the app user.
	local VOLUME_OWNER="$(get_env_parameter "UID"):$(get_env_parameter "GID")"
	if [ -n "${VOLUMES_DIR}" ]; then
		mkdir -p "${VOLUMES_DIR}/app_data/Studio" "${VOLUMES_DIR}/app_data/Products" "${VOLUMES_DIR}/log_data"
		chown_excluding_wopi_keys "${VOLUME_OWNER}" "${VOLUMES_DIR}/app_data"
		chown_excluding_wopi_keys "${VOLUME_OWNER}" "${VOLUMES_DIR}/log_data"
	else
		local PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$PACKAGE_SYSNAME}"
		local PROJECT_FILTER=(--filter "label=com.docker.compose.project=${PROJECT_NAME}" --filter name=app_data --filter name=log_data)
		local VOLUME_NAMES
		mapfile -t VOLUME_NAMES < <(docker volume ls -q "${PROJECT_FILTER[@]}")

		local NAME DEFAULT_VOLUME_NAME
		for NAME in app_data log_data; do
			DEFAULT_VOLUME_NAME="${PROJECT_NAME}_${NAME}"
			docker volume inspect "${DEFAULT_VOLUME_NAME}" &>/dev/null || docker volume create \
				--label "com.docker.compose.project=${PROJECT_NAME}" \
				--label "com.docker.compose.volume=${NAME}" \
				"${DEFAULT_VOLUME_NAME}" >/dev/null || return 1
			VOLUME_NAMES+=("${DEFAULT_VOLUME_NAME}")
		done

		mapfile -t VOLUME_NAMES < <(printf "%s\n" "${VOLUME_NAMES[@]}" | sort -u)
		for VOLUME_NAME in "${VOLUME_NAMES[@]}"; do
			local MOUNT_POINT="$(docker volume inspect --format '{{.Mountpoint}}' "${VOLUME_NAME}")"
			[[ "${VOLUME_NAME}" == *app_data ]] && mkdir -p "${MOUNT_POINT}/Studio" "${MOUNT_POINT}/Products"
			chown_excluding_wopi_keys "${VOLUME_OWNER}" "${MOUNT_POINT}"
		done
	fi
}

install_mysql_server () {
	reconfigure DATABASE_MIGRATION "${DATABASE_MIGRATION}"
	reconfigure MYSQL_DATABASE "${MYSQL_DATABASE}"
	reconfigure MYSQL_USER "${MYSQL_USER}"
	reconfigure MYSQL_PASSWORD "${MYSQL_PASSWORD}"
	reconfigure MYSQL_ROOT_PASSWORD "${MYSQL_ROOT_PASSWORD}"

	if [[ -z ${MYSQL_HOST} ]] && [ "$INSTALL_MYSQL_SERVER" == "true" ]; then
		if [ -n "${VOLUMES_DIR}" ]; then
			mkdir -p "${VOLUMES_DIR}/mysql_data"
			chown $(docker run --rm "$(${DOCKER_COMPOSE} -f ${BASE_DIR}/db.yml config | awk '/image:/ {print $2; exit}')" stat -c '%u:%g' /var/lib/mysql) "${VOLUMES_DIR}/mysql_data"
			chmod $(docker run --rm "$(${DOCKER_COMPOSE} -f ${BASE_DIR}/db.yml config | awk '/image:/ {print $2; exit}')" stat -c '%a' /var/lib/mysql) "${VOLUMES_DIR}/mysql_data"
		fi
		${DOCKER_COMPOSE} -f ${BASE_DIR}/db.yml up -d --force-recreate
	elif [ "$INSTALL_MYSQL_SERVER" == "pull" ]; then
		${DOCKER_COMPOSE} -f ${BASE_DIR}/db.yml pull
	fi
}

install_rabbitmq () {
	if [[ -z ${RABBIT_HOST} ]] && [ "$INSTALL_RABBITMQ" == "true" ]; then
		${DOCKER_COMPOSE} -f ${BASE_DIR}/rabbitmq.yml up -d
	elif [ "$INSTALL_RABBITMQ" == "pull" ]; then
		${DOCKER_COMPOSE} -f ${BASE_DIR}/rabbitmq.yml pull
	fi
}

install_redis () {
	if [[ -z ${REDIS_HOST} ]] && [ "$INSTALL_REDIS" == "true" ]; then
		${DOCKER_COMPOSE} -f ${BASE_DIR}/redis.yml up -d
	elif [ "$INSTALL_REDIS" == "pull" ]; then
		${DOCKER_COMPOSE} -f ${BASE_DIR}/redis.yml pull
	fi
}

install_elasticsearch () {
	if [[ -z ${ELK_HOST} ]] && [ "$INSTALL_ELASTICSEARCH" == "true" ]; then
		if [ -n "${VOLUMES_DIR}" ]; then
			mkdir -p "${VOLUMES_DIR}/os_data"
			chown $(docker run --rm "$(${DOCKER_COMPOSE} -f ${BASE_DIR}/opensearch.yml config | awk '/image:/ {print $2; exit}')" stat -c '%u:%g' /usr/share/opensearch/data) "${VOLUMES_DIR}/os_data"
		fi

		opensearch_set_heap_size "${BASE_DIR}/opensearch.yml"

		${DOCKER_COMPOSE} -f ${BASE_DIR}/opensearch.yml up -d
	elif [ "$INSTALL_ELASTICSEARCH" == "pull" ]; then
		${DOCKER_COMPOSE} -f ${BASE_DIR}/opensearch.yml pull
	fi
}

install_fluent_bit () {
	if [ "$INSTALL_FLUENT_BIT" == "true" ]; then
		[ ! -z "$ELK_HOST" ] && sed -i "s/ELK_CONTAINER_NAME/ELK_HOST/g" $BASE_DIR/fluent.yml ${BASE_DIR}/dashboards.yml

		OPENSEARCH_INDEX="${OPENSEARCH_INDEX:-"${PACKAGE_SYSNAME}-fluent-bit"}"
		if crontab -l | grep -q "${OPENSEARCH_INDEX}"; then
			crontab -l | grep -v "${OPENSEARCH_INDEX}" | crontab -
		fi
		(crontab -l 2>/dev/null; echo "0 0 */1 * * curl -s -X POST $(get_env_parameter 'ELK_SCHEME')://${ELK_HOST:-127.0.0.1}:$(get_env_parameter 'ELK_PORT')/${OPENSEARCH_INDEX}/_delete_by_query -H 'Content-Type: application/json' -d '{\"query\": {\"range\": {\"@timestamp\": {\"lt\": \"now-30d\"}}}}'") | crontab -

		sed -i "s/OPENSEARCH_HOST/${ELK_HOST:-"${PACKAGE_SYSNAME}-opensearch"}/g" "${BASE_DIR}/config/fluent-bit.conf"
		sed -i "s/OPENSEARCH_PORT/$(get_env_parameter "ELK_PORT")/g" ${BASE_DIR}/config/fluent-bit.conf
		sed -i "s/OPENSEARCH_INDEX/${OPENSEARCH_INDEX}/g" ${BASE_DIR}/config/fluent-bit.conf

		reconfigure DASHBOARDS_USERNAME "${DASHBOARDS_USERNAME:-"${PACKAGE_SYSNAME}"}"
		reconfigure DASHBOARDS_PASSWORD "${DASHBOARDS_PASSWORD:-$(get_random_str 20)}"
		
		${DOCKER_COMPOSE} -f ${BASE_DIR}/fluent.yml -f ${BASE_DIR}/dashboards.yml up -d
	elif [ "$INSTALL_FLUENT_BIT" == "pull" ]; then
		${DOCKER_COMPOSE} -f ${BASE_DIR}/fluent.yml -f ${BASE_DIR}/dashboards.yml pull
	fi
}

install_product () {
	if [ "$INSTALL_PRODUCT" == "true" ]; then
		if [ "${UPDATE}" = "true" ]; then
			ACTUAL_CONTAINER="${CONTAINER_NAME}"
			if [ "${DEPLOYMENT_MODE}" = "stack" ] && \
				[ -z "$(docker ps -a -q -f "name=^${CONTAINER_NAME}$")" ] && \
				[ -n "$(docker ps -a -q -f "name=^${PACKAGE_SYSNAME}-api$")" ]; then
				ACTUAL_CONTAINER="${PACKAGE_SYSNAME}-api"
			fi
			LOCAL_CONTAINER_TAG="$(docker inspect --format='{{index .Config.Image}}' "${ACTUAL_CONTAINER}" 2>/dev/null | awk -F':' '{print $2}';)"
			echo "Updating images from tag ${LOCAL_CONTAINER_TAG} to ${DOCKER_TAG}..."

			if [ "$LOCAL_CONTAINER_TAG" != "$DOCKER_TAG" ]; then
				# (DS v3.7.0) Remove legacy service containers after renaming
				for _svc in "files-services" "backup-background-tasks" "ai-service"; do
					docker ps -q --filter "name=^${PACKAGE_SYSNAME}-${_svc}$" | xargs -r docker rm -f
				done

				if [ "${DEPLOYMENT_MODE}" = "stack" ]; then
					${DOCKER_COMPOSE} -f ${BASE_DIR}/apps-stack.yml -f ${BASE_DIR}/proxy.yml down
					if [ "${ACTUAL_CONTAINER}" = "${PACKAGE_SYSNAME}-api" ]; then
						docker ps -a --format '{{.ID}} {{.Image}}' | grep ":${LOCAL_CONTAINER_TAG}$" | awk '{print $1}' | xargs -r docker rm -f
					fi
				else
					compose_with_document_server_mounts "${COMPOSE_FILES[@]}" down
				fi
				docker images --format "{{.Repository}}:{{.Tag}}" | grep ":${LOCAL_CONTAINER_TAG}$" | xargs -r docker rmi
			fi
		fi

		reconfigure ENV_EXTENSION "${ENV_EXTENSION}"
		reconfigure IDENTITY_PROFILE "${IDENTITY_PROFILE:-"prod,server"}"
		reconfigure APP_CORE_MACHINEKEY "${APP_CORE_MACHINEKEY}"
		reconfigure IDENTITY_ENCRYPTION_SECRET "${IDENTITY_ENCRYPTION_SECRET}"
		reconfigure APP_CORE_BASE_DOMAIN "${APP_CORE_BASE_DOMAIN}"
		reconfigure APP_URL_PORTAL "${APP_URL_PORTAL:-"http://${PACKAGE_SYSNAME}-router:8092"}"
		reconfigure EXTERNAL_PORT "${EXTERNAL_PORT}"
		reconfigure EXTERNAL_PORT_HTTPS "${EXTERNAL_PORT_HTTPS}"

		if [[ -z ${MYSQL_HOST} ]] && [ "$INSTALL_MYSQL_SERVER" == "true" ] && [[ -n $(docker ps -q --filter "name=${PACKAGE_SYSNAME}-mysql-server") ]]; then
			wait_mysql_healthy
		fi

		chown_app_volumes || exit 1

		if [ "${DEPLOYMENT_MODE}" = "stack" ]; then
			${DOCKER_COMPOSE} -f "${BASE_DIR}/apps-stack.yml" up -d
			${DOCKER_COMPOSE} -f "${BASE_DIR}/proxy.yml" up -d
		else
			${DOCKER_COMPOSE} -f "${BASE_DIR}/migration-runner.yml" up -d

			if [[ -n $(docker ps -q --filter "name=${PACKAGE_SYSNAME}-migration-runner") ]]; then
				echo -n "Waiting for database migration to complete..."
				timeout 30 bash -c "while [ $(docker wait ${PACKAGE_SYSNAME}-migration-runner) -ne 0 ]; do sleep 1; done;" && echo "OK" || echo "FAILED"
			fi

			compose_with_document_server_mounts "${COMPOSE_FILES[@]}" up -d
		fi

		chown_app_volumes || exit 1

		if [[ -n "${PREVIOUS_ELK_VERSION}" && "$(get_env_parameter "ELK_VERSION")" != "${PREVIOUS_ELK_VERSION}" ]]; then
			docker ps -q -f name=${PACKAGE_SYSNAME}-elasticsearch | xargs -r docker stop
			MYSQL_TAG=$(docker images --format "{{.Tag}}" mysql | head -n1)
			MYSQL_CONTAINER_NAME=$(get_env_parameter "MYSQL_CONTAINER_NAME" | sed "s/\${CONTAINER_PREFIX}/${PACKAGE_SYSNAME}-/g")
			docker run --rm --network="$(get_env_parameter "NETWORK_NAME")" -e MYSQL_PWD="${MYSQL_PASSWORD}" mysql:${MYSQL_TAG:-latest} mysql -h "${MYSQL_HOST:-${MYSQL_CONTAINER_NAME}}" -P "${MYSQL_PORT:-3306}" -u "${MYSQL_USER}" "${MYSQL_DATABASE}" -e "TRUNCATE webstudio_index;"
		fi

		if [ ! -z "${CERTIFICATE_PATH}" ] && [[ ! -z "${APP_DOMAIN_PORTAL}" ]]; then
		    env ${DHPARAM_PATH:+DHPARAM_PATH="$DHPARAM_PATH"} \
			bash $BASE_DIR/config/${PRODUCT}-ssl-setup -f "${APP_DOMAIN_PORTAL}" "${CERTIFICATE_PATH}" "${CERTIFICATE_KEY_PATH}"
		    finish_https_takeover $?
		elif [ ! -z "${LETS_ENCRYPT_DOMAIN}" ] && [ ! -z "${LETS_ENCRYPT_MAIL}" ]; then
		    env ${DHPARAM_PATH:+DHPARAM_PATH="$DHPARAM_PATH"} \
			bash $BASE_DIR/config/${PRODUCT}-ssl-setup "${LETS_ENCRYPT_MAIL}" "${LETS_ENCRYPT_DOMAIN}"
		    finish_https_takeover $?
		elif [[ -n "${CERTIFICATE_KEY_PATH}${CERTIFICATE_PATH}${LETS_ENCRYPT_DOMAIN}${LETS_ENCRYPT_MAIL}" ]]; then
			echo -e "\e[31mERROR:\e[0m Missing required parameters for SSL setup"
			echo "Run 'bash $BASE_DIR/config/${PRODUCT}-ssl-setup --help' for usage information."
		fi

		# Fix for bug 70537 to ensure proper migration to version 3.0.0
		if [ "${UPDATE}" = "true" ] && [ -f "/etc/cron.weekly/${PRODUCT}-letsencrypt" ]; then
			bash $BASE_DIR/config/${PRODUCT}-ssl-setup -r
		fi
	elif [ "$INSTALL_PRODUCT" == "pull" ]; then
		compose_with_document_server_mounts "${COMPOSE_FILES[@]}" pull
	fi
}

# Remove the previous app layer while keeping shared dependencies.
teardown_previous_deployment_mode () {
	echo "Switching deployment mode from ${CURRENT_DEPLOYMENT_MODE} to ${DEPLOYMENT_MODE}; removing the previous app layer (MySQL/OpenSearch/Document Server are kept)..."

	local TARGET_DEPLOYMENT_MODE="${DEPLOYMENT_MODE}"
	DEPLOYMENT_MODE="${CURRENT_DEPLOYMENT_MODE}"
	select_deployment_mode

	# (DS v4.0.0) take over an installation made before the rename to ONLYOFFICE Apps
	local INDEX LEGACY_FILE
	for INDEX in "${!COMPOSE_FILES[@]}"; do
		[ "${COMPOSE_FILES[$INDEX]}" = "-f" ] || [ -f "${COMPOSE_FILES[$INDEX]}" ] && continue
		LEGACY_FILE="${BASE_DIR}/$(basename "${COMPOSE_FILES[$INDEX]}" | sed "s/^${PRODUCT}/${LEGACY_PRODUCT}/")"
		[ -f "${LEGACY_FILE}" ] && COMPOSE_FILES[INDEX]="${LEGACY_FILE}"
	done

	if [ "${CURRENT_DEPLOYMENT_MODE}" = "standalone" ]; then
		compose_with_document_server_mounts "${COMPOSE_FILES[@]}" rm -sf "${PACKAGE_SYSNAME}-${PRODUCT}"
	else
		compose_with_document_server_mounts "${COMPOSE_FILES[@]}" down
	fi

	# standalone bundles Redis/RabbitMQ/Fluent Bit/Dashboards into the single
	# container; the other modes run them as separate containers via their own
	# compose files, which COMPOSE_FILES above never references, so they'd
	# otherwise keep running as unmanaged leftovers under the project.
	if [ "${TARGET_DEPLOYMENT_MODE}" = "standalone" ] && [ "${CURRENT_DEPLOYMENT_MODE}" != "standalone" ]; then
		[ -f "${BASE_DIR}/redis.yml" ] && ${DOCKER_COMPOSE} -f "${BASE_DIR}/redis.yml" down
		[ -f "${BASE_DIR}/rabbitmq.yml" ] && ${DOCKER_COMPOSE} -f "${BASE_DIR}/rabbitmq.yml" down
		[ -f "${BASE_DIR}/fluent.yml" ] && [ -f "${BASE_DIR}/dashboards.yml" ] && \
			${DOCKER_COMPOSE} -f "${BASE_DIR}/fluent.yml" -f "${BASE_DIR}/dashboards.yml" down
	fi

	# The target mode writes its own renewal job if needed.
	rm -f "/etc/cron.weekly/${PRODUCT}-renew-letsencrypt"

	DEPLOYMENT_MODE="${TARGET_DEPLOYMENT_MODE}"
	select_deployment_mode
}

# Profiles for bundled services in standalone mode.
standalone_compose_profiles () {
	local PROFILES=()
	[[ -z ${MYSQL_HOST} ]] && [ "$INSTALL_MYSQL_SERVER" != "false" ] && PROFILES+=(mysql)
	[[ -z ${ELK_HOST} ]] && [ "$INSTALL_ELASTICSEARCH" != "false" ] && PROFILES+=(opensearch)
	{ [ "${DOCUMENT_SERVER_ATTACHED}" = "true" ] || { [[ -z ${DOCUMENT_SERVER_HOST} ]] && [ "$INSTALL_DOCUMENT_SERVER" != "false" ]; }; } && PROFILES+=(docs)
	(IFS=,; echo "${PROFILES[*]}")
}

# Use the same Certbot storage and ACME webroot for issuance, renewal and checks.
standalone_certbot_docker_args () {
	local LE_CONFIG_DIR="$1"
	CERTBOT_DOCKER_ARGS=(--rm
		-v "${LE_CONFIG_DIR}:/etc/letsencrypt"
		-v /var/lib/letsencrypt:/var/lib/letsencrypt
		-v /var/log:/var/log
		-v "${COMPOSE_PROJECT_NAME:-${PACKAGE_SYSNAME}}_webroot_path:/letsencrypt")
}

# Keep standalone Let's Encrypt certs in host storage for renewals.
standalone_issue_letsencrypt () {
	local CERT_NAME="${PRODUCT}"
	local LE_CONFIG_DIR="${BASE_DIR}/certs/letsencrypt"
	mkdir -p "${LE_CONFIG_DIR}"
	[ ! -d "${LE_CONFIG_DIR}/live/${PRODUCT}" ] && [ -d "${LE_CONFIG_DIR}/live/${LEGACY_PRODUCT}" ] && CERT_NAME="${LEGACY_PRODUCT}"
	standalone_certbot_docker_args "${LE_CONFIG_DIR}"

	echo "Generating Let's Encrypt SSL Certificates..."
	if [[ "${LETS_ENCRYPT_DOMAIN}" =~ \*\.[^,]* ]]; then
		docker run "${CERTBOT_DOCKER_ARGS[@]}" certbot/certbot certonly --manual --preferred-challenges dns --key-type rsa \
			--cert-name "${CERT_NAME}" --agree-tos --email "${LETS_ENCRYPT_MAIL}" -d "${LETS_ENCRYPT_DOMAIN}" || return 1
	elif [ "${EXTERNAL_PORT}" = "80" ]; then
		# openresty serves webroot challenges after migrations finish.
		echo -n "Waiting for ${PRODUCT_NAME} to answer on port 80..."
		timeout 600 bash -c 'until [ "$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/.well-known/acme-challenge/probe)" = "404" ]; do sleep 5; done' \
			&& echo "OK" || { echo "FAILED"; return 1; }
		docker run "${CERTBOT_DOCKER_ARGS[@]}" certbot/certbot certonly \
			--expand --webroot -w /letsencrypt --key-type rsa \
			--cert-name "${CERT_NAME}" --non-interactive --agree-tos --email "${LETS_ENCRYPT_MAIL}" -d "${LETS_ENCRYPT_DOMAIN}" || return 1
	else
		docker run "${CERTBOT_DOCKER_ARGS[@]}" --network host certbot/certbot certonly \
			--expand --standalone --http-01-port 80 --key-type rsa \
			--cert-name "${CERT_NAME}" --non-interactive --agree-tos --email "${LETS_ENCRYPT_MAIL}" -d "${LETS_ENCRYPT_DOMAIN}" || return 1
	fi

	CERTIFICATE_PATH="${LE_CONFIG_DIR}/live/${CERT_NAME}/fullchain.pem"
	CERTIFICATE_KEY_PATH="${LE_CONFIG_DIR}/live/${CERT_NAME}/privkey.pem"
}

# Reuse the standard renewal path so mode switches replace the job.
create_standalone_renew_script () {
	local CRON_FILE="/etc/cron.weekly/${PRODUCT}-renew-letsencrypt"
	local LOG_FILE="/var/log/${PRODUCT}-renew-letsencrypt.log"
	local CERTS_DIR="${BASE_DIR}/config/nginx/certs"
	local CRON_PATH
	local APP_GID
	local LE_CONFIG_DIR="${CERTIFICATE_PATH%/live/*}"

	[ -d /etc/cron.weekly ] || { echo "Warning: /etc/cron.weekly does not exist; the Let's Encrypt certificate will not renew automatically." >&2; return 1; }
	CRON_PATH=$(command -v crond || command -v cron) || { echo "Warning: neither crond nor cron is installed; the Let's Encrypt certificate will not renew automatically." >&2; return 1; }
	systemctl enable --now "${CRON_PATH##*/}" >/dev/null 2>&1 || service "${CRON_PATH##*/}" start >/dev/null 2>&1
	APP_GID="$(get_env_parameter "GID")"
	standalone_certbot_docker_args "${LE_CONFIG_DIR}"

	# Covers both standalone_issue_letsencrypt authenticators.
	# Serialize the shared mount arguments with Bash's own quoting.
	cat > "${CRON_FILE}" <<END
#!/bin/bash
# ${PRODUCT} Renew Let's Encrypt SSL Certificates (standalone deployment mode)
echo "[\$(date '+%F %T')] START ${CRON_FILE}" >> "${LOG_FILE}"
$(declare -p CERTBOT_DOCKER_ARGS)
$(command -v docker) run "\${CERTBOT_DOCKER_ARGS[@]}" --network host certbot/certbot renew 2>&1 | tee -a "${LOG_FILE}"
install -m 644 "${CERTIFICATE_PATH}" "${CERTS_DIR}/$(basename "${CERTIFICATE_PATH}")"
install -m 640 -g "${APP_GID}" "${CERTIFICATE_KEY_PATH}" "${CERTS_DIR}/$(basename "${CERTIFICATE_KEY_PATH}")"
$(command -v docker) exec ${CONTAINER_NAME} /usr/local/openresty/bin/openresty -s reload
END
	chmod a+x "${CRON_FILE}"
}

check_standalone_letsencrypt_renewal () {
	[[ "${LETS_ENCRYPT_DOMAIN}" =~ \*\.[^,]* ]] && return 0
	local LE_CONFIG_DIR="${CERTIFICATE_PATH%/live/*}"
	standalone_certbot_docker_args "${LE_CONFIG_DIR}"

	echo -n "Checking Let's Encrypt renewal on the host... "
	if docker run "${CERTBOT_DOCKER_ARGS[@]}" --network host certbot/certbot renew --dry-run >/dev/null; then
		echo "OK"
	else
		echo "FAILED"
		echo "Warning: host-side Let's Encrypt renewal dry-run failed; check /etc/cron.weekly/${PRODUCT}-renew-letsencrypt and /var/log/${PRODUCT}-renew-letsencrypt.log." >&2
	fi

	# The standalone authenticator used with a custom external HTTP port needs host port 80.
	if [ "${EXTERNAL_PORT}" = "80" ]; then
		echo -n "Checking Let's Encrypt renewal in ${PRODUCT_NAME}... "
		if docker exec "${CONTAINER_NAME}" certbot renew --dry-run >/dev/null; then
			echo "OK"
		else
			echo "FAILED"
			echo "Warning: Let's Encrypt renewal dry-run failed in ${CONTAINER_NAME}; check the LETSENCRYPT_CONFIG_DIR mount and Certbot logs." >&2
		fi
	fi
}

install_standalone () {
	sed -i "s~^\(\s*COMPOSE_PROFILES=\).*~\1$(standalone_compose_profiles)~" "${BASE_DIR}/.env"

	if [ "$INSTALL_PRODUCT" == "true" ]; then
		if [ "${UPDATE}" = "true" ]; then
			LOCAL_CONTAINER_TAG="$(docker inspect --format='{{index .Config.Image}}' "${CONTAINER_NAME}" 2>/dev/null | awk -F':' '{print $2}';)"
			echo "Updating images from tag ${LOCAL_CONTAINER_TAG} to ${DOCKER_TAG}..."

			if [ "$LOCAL_CONTAINER_TAG" != "$DOCKER_TAG" ]; then
				compose_with_document_server_mounts "${COMPOSE_FILES[@]}" rm -sf "${PACKAGE_SYSNAME}-${PRODUCT}"
				docker images --format "{{.Repository}}:{{.Tag}}" | grep ":${LOCAL_CONTAINER_TAG}$" | xargs -r docker rmi
			fi
		fi

		reconfigure ENV_EXTENSION "${ENV_EXTENSION}"
		reconfigure GIT_BRANCH "${GIT_BRANCH}"
		reconfigure APP_CORE_BASE_DOMAIN "${APP_CORE_BASE_DOMAIN}"
		# Must stay shared across deployment modes.
		reconfigure APP_CORE_MACHINEKEY "${APP_CORE_MACHINEKEY}"
		reconfigure IDENTITY_ENCRYPTION_SECRET "${IDENTITY_ENCRYPTION_SECRET}"
		# APP_URL_PORTAL stays on the internal router for Docs callbacks.
		reconfigure EXTERNAL_PORT "${EXTERNAL_PORT}"
		reconfigure EXTERNAL_PORT_HTTPS "${EXTERNAL_PORT_HTTPS}"
		reconfigure DATABASE_MIGRATION "${DATABASE_MIGRATION}"
		reconfigure MYSQL_DATABASE "${MYSQL_DATABASE}"
		reconfigure MYSQL_USER "${MYSQL_USER}"
		reconfigure MYSQL_PASSWORD "${MYSQL_PASSWORD}"
		reconfigure MYSQL_ROOT_PASSWORD "${MYSQL_ROOT_PASSWORD}"
		reconfigure DOCUMENT_SERVER_JWT_HEADER "${DOCUMENT_SERVER_JWT_HEADER}"
		reconfigure DOCUMENT_SERVER_JWT_SECRET "${DOCUMENT_SERVER_JWT_SECRET}"

		enable_document_server_env_file "${BASE_DIR}/docker-compose.yml"

		if [ "${DOCUMENT_SERVER_ATTACHED}" = "true" ]; then
			migrate_document_server_data || { echo "Aborting: failed to migrate the existing Document Server's data." >&2; exit 1; }
			enable_document_server_env_file "${BASE_DIR}/docker-compose.yml"
		fi

		opensearch_set_heap_size "${BASE_DIR}/docker-compose.yml"

		chown_app_volumes || exit 1

		# Standalone SSL is controlled by docker-compose env vars.
		local STACK_STARTED="false" CUSTOM_CERT_UP_STATUS
		if [ -z "${CERTIFICATE_PATH}" ] && [ -n "${LETS_ENCRYPT_DOMAIN}" ] && [ -n "${LETS_ENCRYPT_MAIL}" ]; then
			# Webroot challenges need openresty up on :80 first.
			compose_with_document_server_mounts "${COMPOSE_FILES[@]}" up -d || exit 1
			STACK_STARTED="true"
			if ! standalone_issue_letsencrypt; then
				echo "Warning: failed to obtain a Let's Encrypt certificate for ${LETS_ENCRYPT_DOMAIN}; ${PRODUCT_NAME} stays on http://." >&2
				finish_https_takeover 1
			fi
		fi

		if [ -n "${CERTIFICATE_PATH}" ] && [ -n "${APP_DOMAIN_PORTAL}" ]; then
			reconfigure CERTIFICATE_PATH "${CERTIFICATE_PATH}"
			reconfigure CERTIFICATE_KEY_PATH "${CERTIFICATE_KEY_PATH}"
			# Share Certbot's renewal configuration with Apps for host-managed LE certificates.
			if [[ "${CERTIFICATE_PATH}" == */letsencrypt/live/*/fullchain.pem ]]; then
				reconfigure LETSENCRYPT_CONFIG_DIR "${CERTIFICATE_PATH%/live/*}"
			fi
			reconfigure APP_CORE_SERVER_ROOT "https://*$([ "${EXTERNAL_PORT_HTTPS}" = "443" ] || echo ":${EXTERNAL_PORT_HTTPS}")/"
			mkdir -p "${BASE_DIR}/config/nginx/certs"
			cp "${CERTIFICATE_PATH}" "${BASE_DIR}/config/nginx/certs/"
			cp "${CERTIFICATE_KEY_PATH}" "${BASE_DIR}/config/nginx/certs/"
			# Keep the private key group-readable, not world-readable.
			chmod 644 "${BASE_DIR}/config/nginx/certs/$(basename "${CERTIFICATE_PATH}")"
			chown "0:$(get_env_parameter "GID")" "${BASE_DIR}/config/nginx/certs/$(basename "${CERTIFICATE_KEY_PATH}")"
			chmod 640 "${BASE_DIR}/config/nginx/certs/$(basename "${CERTIFICATE_KEY_PATH}")"
			SSL_MODE="custom" SSL_DOMAIN="${LETS_ENCRYPT_DOMAIN:-${APP_DOMAIN_PORTAL}}" \
				SSL_CERT_PATH="/etc/nginx/certs/$(basename "${CERTIFICATE_PATH}")" \
				SSL_KEY_PATH="/etc/nginx/certs/$(basename "${CERTIFICATE_KEY_PATH}")" \
				compose_with_document_server_mounts "${COMPOSE_FILES[@]}" up -d
			CUSTOM_CERT_UP_STATUS=$?
			finish_https_takeover "${CUSTOM_CERT_UP_STATUS}"
			[ "${CUSTOM_CERT_UP_STATUS}" -eq 0 ] || exit "${CUSTOM_CERT_UP_STATUS}"
			if [[ "${CERTIFICATE_PATH}" == */letsencrypt/live/*/fullchain.pem ]]; then
				create_standalone_renew_script && check_standalone_letsencrypt_renewal
			fi
		elif [[ -n "${CERTIFICATE_KEY_PATH}${CERTIFICATE_PATH}" ]] || { [ "${STACK_STARTED}" = "false" ] && [[ -n "${LETS_ENCRYPT_DOMAIN}${LETS_ENCRYPT_MAIL}" ]]; }; then
			echo -e "\e[31mERROR:\e[0m Missing required parameters for SSL setup"
			exit 1
		elif [ "${STACK_STARTED}" = "false" ]; then
			compose_with_document_server_mounts "${COMPOSE_FILES[@]}" up -d || exit 1
		fi

		chown_app_volumes || exit 1
		finish_document_server_migration || exit 1
	elif [ "$INSTALL_PRODUCT" == "pull" ]; then
		compose_with_document_server_mounts "${COMPOSE_FILES[@]}" pull
	fi
}

make_swap () {
	DISK_REQUIREMENTS=6144 #6Gb free space
	MEMORY_REQUIREMENTS=12000 #RAM ~12Gb

	AVAILABLE_DISK_SPACE=$(df -Pm / | awk 'NR == 2 { print $4 }')
	TOTAL_MEMORY=$(free --mega | awk '/^Mem:/ { print $2 }')
	EXIST=$(swapon -s | awk '{ print $1 }' | { grep -x ${SWAPFILE} || true; })

	if [[ -z $EXIST ]] && [ ${TOTAL_MEMORY} -lt ${MEMORY_REQUIREMENTS} ] && [ ${AVAILABLE_DISK_SPACE} -gt ${DISK_REQUIREMENTS} ]; then

		if [ "${DIST}" == "Ubuntu" ] || [ "${DIST}" == "Debian" ]; then
			fallocate -l 6G ${SWAPFILE}
		else
			dd if=/dev/zero of=${SWAPFILE} count=6144 bs=1MiB
		fi

		chmod 600 ${SWAPFILE}
		mkswap ${SWAPFILE}
		swapon ${SWAPFILE}
		awk -v swapfile="${SWAPFILE}" '$1 == swapfile && $3 == "swap" { found = 1 } END { exit !found }' /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
	fi
}

offline_check_docker_image() {
	[ ! -f "$1" ] && { echo "Error: File '$1' does not exist."; exit 1; }
	${DOCKER_COMPOSE} -f "$1" config | grep -oP 'image:\s*\K\S+' | while IFS= read -r IMAGE_TAG; do
		docker images --format="{{.Repository}}:{{.Tag}}" "${IMAGE_TAG}"  | grep -q "${IMAGE_TAG%%:*}" || { echo "Error: The image '${IMAGE_TAG}' is not found in the local Docker registry."; kill -s TERM $PID; }
	done
}

check_registry_connection() {
	get_tag_from_registry ${IMAGE_NAME}
	[ -z "${TAGS_RESP[*]}" ] && { echo -e "Unable to download tags from ${REGISTRY_URL:-https://hub.docker.com}.\nTry specifying another docker registry URL using -reg"; exit 1; }
}

check_docker_compose() {
	local COMPOSE_REQ=2018000 VERSION
	for DOCKER_COMPOSE in "docker compose" docker-compose; do
		VERSION=$(${DOCKER_COMPOSE} version --short 2>/dev/null) || continue
		awk -F. -v R="$COMPOSE_REQ" 'NF>=3{exit !($1*1e6+$2*1e3+$3>=R)}' <<<"${VERSION%%[^0-9.]*}" && return 0
	done
	return 1
}

dependency_installation() {
	[ "$NON_INTERACTIVE" = "true" ] && export NEEDRESTART_MODE=a

	[ "${OFFLINE_INSTALLATION}" = "false" ] && is_command_exists apt-get && apt-get -y update -qq

	install_package tar
	install_package curl
	install_package netstat net-tools

	[ "$INSTALL_FLUENT_BIT" = "true" ] && install_package crontab "cron|cronie"

	if ! is_command_exists jq ; then
		if is_command_exists yum && ! rpm -q epel-release > /dev/null 2>&1; then
			[ "${OFFLINE_INSTALLATION}" = "false" ] && rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-${REV}.noarch.rpm
		fi
		install_package jq
	fi

	if ! is_command_exists docker || [ "$(docker --version | awk -F'[ ,.]' '{print $3}')" -lt 18 ]; then
		[ "${OFFLINE_INSTALLATION}" = "false" ] && install_docker || { echo "docker not installed or outdated version"; exit 1; }
	else
		systemctl start docker
	fi

	check_docker_compose || { [ "${OFFLINE_INSTALLATION}" = "false" ] && install_docker_compose || { echo "docker compose not installed or outdated version"; exit 1; }; }
}

check_docker_image () {
	reconfigure REGISTRY "${REGISTRY_URL:+$(sed -E 's~^https?://~~; s~/*$~~' <<< "$REGISTRY_URL")/}"
	reconfigure STATUS "${STATUS}"
	reconfigure INSTALLATION_TYPE "${INSTALLATION_TYPE}"
	reconfigure NETWORK_NAME "${NETWORK_NAME}"
	reconfigure VOLUMES_DIR "${VOLUMES_DIR}"
	reconfigure EXTRA_HOSTS "${EXTRA_HOSTS}"
	
	reconfigure MYSQL_VERSION "${MYSQL_VERSION}"
	reconfigure ELK_VERSION "${ELK_VERSION}"
	reconfigure DOCUMENT_SERVER_IMAGE_NAME "${DOCUMENT_SERVER_IMAGE_NAME}:\${DOCUMENT_SERVER_VERSION}"
	reconfigure DOCUMENT_SERVER_VERSION "${DOCUMENT_SERVER_VERSION:-$(get_available_version "$DOCUMENT_SERVER_IMAGE_NAME")}"

	DOCKER_TAG="${DOCKER_TAG:-$(get_available_version ${IMAGE_NAME})}"
	reconfigure DOCKER_TAG "${DOCKER_TAG}"
	if [ "${OFFLINE_INSTALLATION}" != "false" ]; then
		if [ "${DEPLOYMENT_MODE}" = "standalone" ]; then
			[ "$INSTALL_PRODUCT" == "true" ] && offline_check_docker_image "${BASE_DIR}/docker-compose.yml"
		else
			[ "$INSTALL_MYSQL_SERVER" == "true" ]       && offline_check_docker_image ${BASE_DIR}/db.yml
			[ "$INSTALL_RABBITMQ" == "true" ]           && offline_check_docker_image ${BASE_DIR}/rabbitmq.yml
			[ "$INSTALL_REDIS" == "true" ]              && offline_check_docker_image ${BASE_DIR}/redis.yml
			[ "$INSTALL_FLUENT_BIT" == "true" ]         && offline_check_docker_image ${BASE_DIR}/fluent.yml
			[ "$INSTALL_FLUENT_BIT" == "true" ]         && offline_check_docker_image ${BASE_DIR}/dashboards.yml
			[ "$INSTALL_ELASTICSEARCH" == "true" ]      && offline_check_docker_image ${BASE_DIR}/opensearch.yml
			[ "$INSTALL_DOCUMENT_SERVER" == "true" ]    && offline_check_docker_image ${BASE_DIR}/ds.yml

			if [ "$INSTALL_PRODUCT" == "true" ]; then
				for SVC in "${SERVICES[@]}"; do offline_check_docker_image "${BASE_DIR}/${SVC}.yml"; done
			fi
		fi
	fi
}

services_check_connection () {
	# Fixes issues with variables when upgrading to v1.1.3
	HOSTS=("ELK_HOST" "REDIS_HOST" "RABBIT_HOST" "MYSQL_HOST")
	for HOST in "${HOSTS[@]}"; do [[ "${!HOST}" == *CONTAINER_PREFIX* || "${!HOST}" == *$PACKAGE_SYSNAME* ]] && export "$HOST="; done
	[[ "${APP_URL_PORTAL}" == *${PACKAGE_SYSNAME}-proxy* ]] && APP_URL_PORTAL=""

	if [[ ! -z "$MYSQL_HOST" ]]; then
		establish_conn ${MYSQL_HOST} "${MYSQL_PORT:-3306}" "MySQL"
		reconfigure MYSQL_HOST "${MYSQL_HOST}"
		reconfigure MYSQL_PORT "${MYSQL_PORT:-3306}"
	fi
	if [[ ! -z "$DOCUMENT_SERVER_HOST" ]]; then
		APP_URL_PORTAL=${APP_URL_PORTAL:-"http://$(curl -s -4 ifconfig.me):${EXTERNAL_PORT}"}
		[ "${DOCUMENT_SERVER_ATTACHED}" = "true" ] || establish_conn ${DOCUMENT_SERVER_HOST} ${DOCUMENT_SERVER_PORT} "${PACKAGE_SYSNAME^^} Docs"
		reconfigure DOCUMENT_SERVER_URL_EXTERNAL "${DOCUMENT_SERVER_URL_EXTERNAL}"
		reconfigure DOCUMENT_SERVER_URL_PUBLIC "${DOCUMENT_SERVER_URL_EXTERNAL}"
	fi
	if [[ ! -z "$RABBIT_HOST" ]]; then
		establish_conn ${RABBIT_HOST} "${RABBIT_PORT:-5672}" "RabbitMQ"
		reconfigure RABBIT_PROTOCOL "${RABBIT_PROTOCOL:-amqp}"
		reconfigure RABBIT_HOST "${RABBIT_HOST}"
		reconfigure RABBIT_PORT "${RABBIT_PORT:-5672}"
		reconfigure RABBIT_USER_NAME "${RABBIT_USER_NAME}"
		reconfigure RABBIT_PASSWORD "${RABBIT_PASSWORD}"
		reconfigure RABBIT_VIRTUAL_HOST "${RABBIT_VIRTUAL_HOST:-/}"
	fi
	if [[ ! -z "$REDIS_HOST" ]]; then
		establish_conn ${REDIS_HOST} "${REDIS_PORT:-6379}" "Redis"
		reconfigure REDIS_HOST "${REDIS_HOST}"
		reconfigure REDIS_PORT "${REDIS_PORT:-6379}"
		reconfigure REDIS_USER_NAME "${REDIS_USER_NAME}"
		reconfigure REDIS_PASSWORD "${REDIS_PASSWORD}"
	fi
	if [[ ! -z "$ELK_HOST" ]]; then
		establish_conn ${ELK_HOST} "${ELK_PORT:-9200}" "search engine"
		reconfigure ELK_SCHEME "${ELK_SCHEME:-http}"
		reconfigure ELK_HOST "${ELK_HOST}"
		reconfigure ELK_PORT "${ELK_PORT:-9200}"
	fi
}

start_installation () {
	root_checking
	
	select_deployment_mode
	# Avoid printing this again during mode-switch teardown.
	if [ "${DEPLOYMENT_MODE}" = "standalone" ] && { [ "${INSTALL_RABBITMQ_SET}" = "true" ] || [ "${INSTALL_REDIS_SET}" = "true" ]; }; then
		echo "Note: --installrabbitmq/--installredis are ignored in --deployment-mode standalone (no separate Redis/RabbitMQ containers)."
	fi
	set_installation_type_data

	get_os_info
	check_os_info
	check_kernel

	dependency_installation

	if [ "$SKIP_HARDWARE_CHECK" != "true" ]; then
		check_hardware
	fi

	if [ "$MAKESWAP" == "true" ]; then
		make_swap
	fi

	docker_login

	[ "${OFFLINE_INSTALLATION}" = "false" ] && check_registry_connection

	create_network

	# A retained .env is also needed after uninstall, when no Apps container
	# remains to trigger UPDATE. Restore storage paths and ports before checks.
	if [ "$UPDATE" = "true" ] || [ -f "${BASE_DIR}/.env" ]; then
		set_apps_params
	fi
	detect_existing_document_server || { echo "Cannot safely adopt the existing Document Server." >&2; exit 1; }

	if [ "$UPDATE" != "true" ]; then
		check_ports
	fi

	domain_check

	set_docs_url_external
	set_jwt_secret
	set_jwt_header

	set_secrets

	set_mysql_params

	if [ -n "${CURRENT_DEPLOYMENT_MODE}" ] && [ "${CURRENT_DEPLOYMENT_MODE}" != "${DEPLOYMENT_MODE}" ]; then
		teardown_previous_deployment_mode
	fi

	download_files || exit 1

	check_docker_image

	services_check_connection

	if [ "${DEPLOYMENT_MODE}" = "standalone" ]; then
		install_standalone
	else
		install_elasticsearch

		install_fluent_bit

		install_mysql_server

		install_rabbitmq

		install_redis

		install_document_server

		install_product
	fi

	echo ""
	echo "Thank you for installing ${PRODUCT_NAME}."
	echo "In case you have any questions contact us via http://support.${PACKAGE_SYSNAME}.com or visit our forum at http://community.${PACKAGE_SYSNAME}.com"
	echo ""

	exit 0
}

[[ $UNINSTALL != true ]] && start_installation || uninstall
