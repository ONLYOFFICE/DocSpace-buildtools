#!/bin/bash

 #
 # (c) Copyright Ascensio System SIA 2025
 #
 # This program is a free software product. You can redistribute it and/or
 # modify it under the terms of the GNU Affero General Public License (AGPL)
 # version 3 as published by the Free Software Foundation. In accordance with
 # Section 7(a) of the GNU AGPL its Section 15 shall be amended to the effect
 # that Ascensio System SIA expressly excludes the warranty of non-infringement
 # of any third-party rights.
 #
 # This program is distributed WITHOUT ANY WARRANTY; without even the implied
 # warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. For
 # details, see the GNU AGPL at: http://www.gnu.org/licenses/agpl-3.0.html
 #
 # You can contact Ascensio System SIA at 20A-12 Ernesta Birznieka-Upisha
 # street, Riga, Latvia, EU, LV-1050.
 #
 # The interactive user interfaces in modified source and object code versions
 # of the Program must display Appropriate Legal Notices, as required under
 # Section 5 of the GNU AGPL version 3.
 #
 # Pursuant to Section 7(b) of the License you must retain the original Product
 # logo when distributing the program. Pursuant to Section 7(e) we decline to
 # grant you any rights under trademark law for use of our trademarks.
 #
 # All the Product's GUI elements, including illustrations and icon sets, as
 # well as technical writing content are licensed under the terms of the
 # Creative Commons Attribution-ShareAlike 4.0 International. See the License
 # terms at http://creativecommons.org/licenses/by-sa/4.0/legalcode
 #

PACKAGE_SYSNAME="onlyoffice"
PRODUCT_NAME="DocSpace"
PRODUCT=$(tr '[:upper:]' '[:lower:]' <<< ${PRODUCT_NAME})
BASE_DIR="/app/$PACKAGE_SYSNAME"
STATUS=""
DOCKER_TAG=""
INSTALLATION_TYPE="ENTERPRISE"
IMAGE_NAME="${PACKAGE_SYSNAME}/${STATUS}${PRODUCT}-api"
CONTAINER_NAME="${PACKAGE_SYSNAME}-api"
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

OFFLINE_INSTALLATION="false"
SKIP_HARDWARE_CHECK="false"

SERVICES=(migration-runner identity notify "${PRODUCT}" healthchecks proxy)
COMPOSE_FILES=($(printf '%s\n' "${SERVICES[@]}" | sed "s|^|-f ${BASE_DIR}/|; s|\$|.yml|"));

EXTERNAL_PORT="80"
ARGS_SCRIPT="install-Docker-args.sh"
DOWNLOAD_URL_PREFIX="https://download.${PACKAGE_SYSNAME}.com/${PRODUCT}"
GIT_BRANCH=$(echo "$@" | grep -oP '(?<=-gb )\S+')

if [[ -n "${GIT_BRANCH:-}" ]]; then
  DOWNLOAD_URL_PREFIX="https://raw.githubusercontent.com/${PACKAGE_SYSNAME^^}/${PRODUCT}-buildtools/${GIT_BRANCH}/install/OneClickInstall"
fi

[[ "$LOCAL_SCRIPTS" = "true" ]] || [[ "$OFFLINE_INSTALLATION" = "true" ]] && source "./${ARGS_SCRIPT}" || source <(curl "${DOWNLOAD_URL_PREFIX}/${ARGS_SCRIPT}")

uninstall() {
    read -p "Uninstall all dependencies (mysql, opensearch and others)? (Y/n): " REMOVE_DATA_SERVICES

	if [[ "${REMOVE_DATA_SERVICES,,}" =~ ^(y|yes)?$ ]]; then
		SERVICES+=("db" "rabbitmq" "redis" "opensearch" "dashboards" "fluent")
	fi

    for SERVICE in "${SERVICES[@]}" "ds"; do
        if [[ -f "$BASE_DIR/$SERVICE.yml" ]]; then
            echo "Uninstallation of  $SERVICE and its volumes..."
            docker-compose -f "$BASE_DIR/$SERVICE.yml" down -v || echo "Failed to remove $SERVICE."
        fi
    done

	docker network rm "${NETWORK_NAME}" 2>/dev/null && NETWORK_REMOVED=true || echo "Failed to remove network ${NETWORK_NAME}."

	read -p "Do you want to retain data (keep .env file)? (Y/n): " KEEP_DATA

	if [[ "$NETWORK_REMOVED" == "true" && -d "$BASE_DIR" ]]; then
		if [[ "${KEEP_DATA,,}" =~ ^(y|yes)?$ ]]; then
			find "$BASE_DIR" -mindepth 1 ! -name ".env" -exec rm -rf {} +
		else
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
        MACH=$(uname -m)
		if [ "${MACH}" != "x86_64" ]; then
			echo "Currently only supports 64bit OS's"
			exit 1
		fi

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

	if [ -f /etc/needrestart/needrestart.conf ]; then
		sed -e "s_#\$nrconf{restart}_\$nrconf{restart}_" -e "s_\(\$nrconf{restart} =\).*_\1 'a';_" -i /etc/needrestart/needrestart.conf
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
	AVAILABLE_DISK_SPACE=$(df -m /  | tail -1 | awk '{ print $4 }')

	if [ ${AVAILABLE_DISK_SPACE} -lt ${DISK_REQUIREMENTS} ]; then
		echo "Minimal requirements are not met: need at least $DISK_REQUIREMENTS MB of free HDD space"
		exit 1
	fi

	TOTAL_MEMORY=$(free --mega | grep -oP '\d+' | head -n 1)

	if [ ${TOTAL_MEMORY} -lt ${MEMORY_REQUIREMENTS} ]; then
		echo "Minimal requirements are not met: need at least $MEMORY_REQUIREMENTS MB of RAM"
		exit 1
	fi

	CPU_CORES_NUMBER=$(grep -c ^processor /proc/cpuinfo)

	if [ ${CPU_CORES_NUMBER} -lt ${CORE_REQUIREMENTS} ]; then
		echo "The system does not meet the minimal hardware requirements. CPU with at least $CORE_REQUIREMENTS cores is required"
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
	curl -sL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
	chmod +x /usr/bin/docker-compose
}

check_ports () {
	RESERVED_PORTS=()
	ARRAY_PORTS=()
	USED_PORTS=""

	if [ "${EXTERNAL_PORT//[0-9]}" = "" ]; then
		for RESERVED_PORT in "${RESERVED_PORTS[@]}"
		do
			if [ "$RESERVED_PORT" -eq "$EXTERNAL_PORT" ] ; then
				echo "External port $EXTERNAL_PORT is reserved. Select another port"
				exit 1
			fi
		done
	else
		echo "Invalid external port $EXTERNAL_PORT"
		exit 1
	fi

	if [ "$INSTALL_PRODUCT" == "true" ]; then
		ARRAY_PORTS+=("$EXTERNAL_PORT")
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

	if [ "${DIST}" == "Ubuntu" ] || [ "${DIST}" == "Debian" ] || [[ "${DIST}" == CentOS* ]] || [ "${DIST}" == "Fedora" ]; then

		curl -fsSL https://get.docker.com | bash
		systemctl start docker
		systemctl enable docker

	elif [[ "${DIST}" == Red\ Hat\ Enterprise\ Linux* ]]; then

		if [[ "${REV}" -gt "7" ]]; then
			yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine podman runc > null
			yum install -y yum-utils
			yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
			yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
			systemctl start docker
			systemctl enable docker
		else
			echo ""
			echo "Your operating system does not allow Docker CE installation."
			echo "You can install Docker EE using the manual here - https://docs.docker.com/engine/installation/linux/rhel/"
			echo ""
			exit 1
		fi

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

read_continue_installation () {
	[ "$NON_INTERACTIVE" = "true" ] && INSTALLATION_CHOICE="Y" && return 0

	while true; do
        read -p "Continue installation [Y/C/N]? " CHOICE
        case "$CHOICE" in
            [yY]) INSTALLATION_CHOICE="Y"; return 0 ;;
            [cC]) INSTALLATION_CHOICE="C"; return 0 ;;
            [nN]) exit 0 ;;
            *) echo "Please, enter Y, C or N" ;;
        esac
    done
}

domain_check () {
	APP_DOMAIN_PORTAL=$(cut -d ',' -f 1 <<< "$LETS_ENCRYPT_DOMAIN")
	APP_DOMAIN_PORTAL=${APP_DOMAIN_PORTAL:-${APP_URL_PORTAL:-$(get_env_parameter "APP_URL_PORTAL" "${PACKAGE_SYSNAME}-files" | awk -F[/:] '{if ($1 == "https") print $4; else print ""}')}}

	while IFS= read -r DOMAIN; do
		IP_ADDRESS=$( [ -n "${DOMAIN}" ] && ping -c 1 -W 1 ${DOMAIN} | grep -oP '(\d+\.\d+\.\d+\.\d+)' | head -n 1 )
		if [[ -n "$IP_ADDRESS" && "$IP_ADDRESS" =~ ^(10\.|127\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]]; then
			LOCAL_RESOLVED_DOMAINS+="$DOMAIN"
		fi
	done <<< "${APP_DOMAIN_PORTAL:-$(dig +short -x "$(curl -s -4 ifconfig.me)" | sed 's/\.$//')}"
	
	# check if the domain is a loopback IP or NAT
	if [[ -n "${LOCAL_RESOLVED_DOMAINS}" ]] || [[ $(ip route get 8.8.8.8 | awk '{print $7}') != $(curl -s -4 ifconfig.me) ]]; then 
		DOCKER_DAEMON_FILE="/etc/docker/daemon.json"
		if ! grep -q '"dns"' "$DOCKER_DAEMON_FILE" 2>/dev/null; then
			echo "DNS issue detected for ${APP_DOMAIN_PORTAL:-$LOCAL_RESOLVED_DOMAINS} (loopback IP or NAT)."
			echo "[Y] Use Google DNS | [C] Use custom DNS | [N] Cancel installation"
			if read_continue_installation; then
				case "$INSTALLATION_CHOICE" in
					Y)  DNS=("8.8.8.8" "8.8.4.4") ;;
					C)  while true; do
							read -p "Enter custom DNS (e.g. 8.8.8.8 8.8.4.4): " INPUT; IFS=' ' read -ra DNS <<< "$INPUT"
							for IP in "${DNS[@]}"; do 
								[[ $IP =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "Invalid DNS: $IP"; continue 2; }
							done && break
						done ;;
				esac
				if ((${#DNS[@]})); then
					echo "Updating Docker DNS config with: ${DNS[*]}"
					jq -e . "${DOCKER_DAEMON_FILE}" > /dev/null 2>&1 || echo '{}' > "${DOCKER_DAEMON_FILE}"
					echo "$(jq --argjson dns "$(printf '%s\n' "${DNS[@]}" | jq -R . | jq -s .)" '.dns = $dns' "${DOCKER_DAEMON_FILE}")" > "${DOCKER_DAEMON_FILE}"
					systemctl restart docker || { echo "Failed to restart Docker service"; exit 1; }
				fi
			fi
		fi
	fi

	APP_URL_PORTAL=${APP_DOMAIN_PORTAL:+http://${APP_DOMAIN_PORTAL}:${EXTERNAL_PORT}}
}

establish_conn() {
	echo -n "Trying to establish $3 connection... "

	exec {FD}<> /dev/tcp/${1}/${2} && { exec {FD}>&-; echo "OK"; } || { echo "FAILURE"; exit 1; }
}

get_env_parameter () {
	local PARAMETER_NAME=$1
	local CONTAINER_NAME=$2

	if [[ -z ${PARAMETER_NAME} ]]; then
		echo "Empty parameter name"
		exit 1
	fi

	if is_command_exists docker ; then
		[ -n "$CONTAINER_NAME" ] && CONTAINER_EXIST=$(docker ps -aqf "name=$CONTAINER_NAME")

		if [[ -n ${CONTAINER_EXIST} ]]; then
			VALUE=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' ${CONTAINER_NAME} | grep "${PARAMETER_NAME}=" | sed 's/^.*=//')
		fi
	fi

	if [ -z ${VALUE} ] && [ -f ${BASE_DIR}/.env ]; then
		VALUE=$(awk -F= "/${PARAMETER_NAME}/ {print \$2}" ${BASE_DIR}/.env | tr -d '\r')
	fi

	echo ${VALUE//\"}
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

	mapfile -t TAGS_RESP < <(curl -s -H "${AUTH_HEADER}" -X GET "${REGISTRY_TAGS_URL}" | jq -r "${JQ_FILTER}")
}

get_available_version () {
	[ "${OFFLINE_INSTALLATION}" = "false" ] && get_tag_from_registry ${1} || mapfile -t TAGS_RESP < <(docker images --format "{{.Tag}}" "${1}")

	VERSION_REGEX='^[0-9]+\.[0-9]+(\.[0-9]+){0,2}$'
	[ ${#TAGS_RESP[@]} -eq 1 ] && LATEST_TAG="${TAGS_RESP[0]}" || \
    LATEST_TAG=$(printf "%s\n" "${TAGS_RESP[@]}" | grep -E "$([[ $GIT_BRANCH == "develop" && -n $STATUS ]] && echo '^develop\.[0-9]+$' || echo "$VERSION_REGEX")" | sort -V | tail -n 1)
	LATEST_TAG=${LATEST_TAG:-${STATUS:+$(printf "%s\n" "${TAGS_RESP[@]}" | sort -V | tail -n 1)}} #Fix for 4testing develop tags

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

set_docs_url_external () {
	DOCUMENT_SERVER_URL_EXTERNAL=${DOCUMENT_SERVER_URL_EXTERNAL:-$(get_env_parameter "DOCUMENT_SERVER_URL_EXTERNAL" "${CONTAINER_NAME}")}

	if [[ ! -z ${DOCUMENT_SERVER_URL_EXTERNAL} ]] && [[ $DOCUMENT_SERVER_URL_EXTERNAL =~ ^(https?://)?([^:/]+)(:([0-9]+))?(/.*)?$ ]]; then
		[[ -z ${BASH_REMATCH[1]} ]] && DOCUMENT_SERVER_URL_EXTERNAL="http://$DOCUMENT_SERVER_URL_EXTERNAL"
		DOCUMENT_SERVER_PROTOCOL="${BASH_REMATCH[1]}"
		DOCUMENT_SERVER_HOST="${BASH_REMATCH[2]}"
		DOCUMENT_SERVER_PORT="${BASH_REMATCH[4]:-"80"}"
	fi
}

set_jwt_secret () {
	DOCUMENT_SERVER_JWT_SECRET="${DOCUMENT_SERVER_JWT_SECRET:-$(get_env_parameter "JWT_SECRET" "${PACKAGE_SYSNAME}-document-server")}"
	DOCUMENT_SERVER_JWT_SECRET="${DOCUMENT_SERVER_JWT_SECRET:-$(get_env_parameter "DOCUMENT_SERVER_JWT_SECRET" "${CONTAINER_NAME}")}"
	DOCUMENT_SERVER_JWT_SECRET="${DOCUMENT_SERVER_JWT_SECRET:-$(get_random_str 32)}"
}

set_jwt_header () {
	DOCUMENT_SERVER_JWT_HEADER="${DOCUMENT_SERVER_JWT_HEADER:-$(get_env_parameter "JWT_HEADER" "${PACKAGE_SYSNAME}-document-server")}"
	DOCUMENT_SERVER_JWT_HEADER="${DOCUMENT_SERVER_JWT_HEADER:-$(get_env_parameter "DOCUMENT_SERVER_JWT_HEADER" "${CONTAINER_NAME}")}"
	DOCUMENT_SERVER_JWT_HEADER="${DOCUMENT_SERVER_JWT_HEADER:-"AuthorizationJwt"}"
}

set_secrets () {
	APP_CORE_MACHINEKEY="${APP_CORE_MACHINEKEY:-$(get_env_parameter "APP_CORE_MACHINEKEY" "${CONTAINER_NAME}")}"
	[ "$UPDATE" != "true" ] && APP_CORE_MACHINEKEY="${APP_CORE_MACHINEKEY:-$(get_random_str 12)}"
	IDENTITY_ENCRYPTION_SECRET="${IDENTITY_ENCRYPTION_SECRET:-$(get_env_parameter "IDENTITY_ENCRYPTION_SECRET" "${IDENTITY_CONTAINER_NAME}")}"
	[ "${UPDATE}" = "true" ] && IDENTITY_ENCRYPTION_SECRET="${IDENTITY_ENCRYPTION_SECRET:-"secret"}" # (DS v3.1.0) fix encryption key generation issue
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

set_docspace_params() {
	REGISTRY=${REGISTRY:-$(get_env_parameter "REGISTRY")}

	ENV_EXTENSION=${ENV_EXTENSION:-$(get_env_parameter "ENV_EXTENSION" "${CONTAINER_NAME}")}
	VOLUMES_DIR=${VOLUMES_DIR:-$(get_env_parameter "VOLUMES_DIR")}
	APP_CORE_BASE_DOMAIN=${APP_CORE_BASE_DOMAIN:-$(get_env_parameter "APP_CORE_BASE_DOMAIN" "${CONTAINER_NAME}")}
	EXTERNAL_PORT=${EXTERNAL_PORT:-$(get_env_parameter "EXTERNAL_PORT" "${CONTAINER_NAME}")}

	PREVIOUS_ELK_VERSION=$(get_env_parameter "ELK_VERSION")
	ELK_SCHEME=${ELK_SCHEME:-$(get_env_parameter "ELK_SCHEME" "${CONTAINER_NAME}")}
    # (DS v3.2.0) fallback for legacy ELK_SHEME
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
	if is_command_exists docker; then
		if [ -n "$(docker ps -a -q -f "name=^${PACKAGE_SYSNAME}-dotnet-services$")" ]; then
			STACK_MODE=true; CONTAINER_NAME="${PACKAGE_SYSNAME}-dotnet-services"
		fi
		UPDATE=${UPDATE:-$(test -n "$(docker ps -aqf name=${CONTAINER_NAME})" && echo true)}
	fi
	if [ -z "${DOCUMENT_SERVER_IMAGE_NAME}" ]; then
		DOCUMENT_SERVER_IMAGE_NAME="${PACKAGE_SYSNAME}/${STATUS}documentserver"
		case "${INSTALLATION_TYPE}" in
			"DEVELOPER") DOCUMENT_SERVER_IMAGE_NAME+="-de" ;;
			"ENTERPRISE") DOCUMENT_SERVER_IMAGE_NAME+="-ee" ;;
		esac
	fi
}

download_files () {
	[ "${OFFLINE_INSTALLATION}" = "false" ] && echo -n "Downloading configuration files to ${BASE_DIR}..." || echo "Unzip docker.tar.gz to ${BASE_DIR}..."

	rm -rf "${BASE_DIR:?}"
	mkdir -p ${BASE_DIR}

	
	if [ "${OFFLINE_INSTALLATION}" = "false" ]; then
		if [ -z "${GIT_BRANCH}" ]; then
			DOWNLOAD_URL="https://download.${PACKAGE_SYSNAME}.com/${PRODUCT}/docker.tar.gz"
		else
			DOWNLOAD_URL="https://codeload.github.com/${PACKAGE_SYSNAME}/${PRODUCT}-buildtools/tar.gz/${GIT_BRANCH}"
			STRIP_COMPONENTS="--strip-components=3 --wildcards */install/docker/*"
		fi

		curl -sL "${DOWNLOAD_URL}" | tar -xzf - -C "${BASE_DIR}" ${STRIP_COMPONENTS}
	else
		if [ -f "$(dirname "$0")/docker.tar.gz" ]; then
			tar -xf "$(dirname "$0")/docker.tar.gz" -C "${BASE_DIR}"
		else
			echo "Error: docker.tar.gz not found in the same directory as the script."
			echo "You need to download the docker.tar.gz file from https://download.${PACKAGE_SYSNAME}.com/${PRODUCT}/docker.tar.gz"
			exit 1
		fi
	fi

	echo "OK"
}

reconfigure () {
	local VARIABLE_NAME="$1"
	local VARIABLE_VALUE="$2"

	if [[ -n ${VARIABLE_VALUE} ]]; then
		sed -i "s~${VARIABLE_NAME}=.*~${VARIABLE_NAME}=${VARIABLE_VALUE}~g" $BASE_DIR/.env
	fi
}

install_mysql_server () {
	reconfigure DATABASE_MIGRATION ${DATABASE_MIGRATION}
	reconfigure MYSQL_DATABASE ${MYSQL_DATABASE}
	reconfigure MYSQL_USER ${MYSQL_USER}
	reconfigure MYSQL_PASSWORD ${MYSQL_PASSWORD}
	reconfigure MYSQL_ROOT_PASSWORD ${MYSQL_ROOT_PASSWORD}

	if [[ -z ${MYSQL_HOST} ]] && [ "$INSTALL_MYSQL_SERVER" == "true" ]; then
		if [ -n "${VOLUMES_DIR}" ]; then
			mkdir -p "${VOLUMES_DIR}/mysql_data"
			chown $(docker run --rm "$(docker-compose -f ${BASE_DIR}/db.yml config | awk '/image:/ {print $2; exit}')" stat -c '%u:%g' /var/lib/mysql) "${VOLUMES_DIR}/mysql_data"
			chmod $(docker run --rm "$(docker-compose -f ${BASE_DIR}/db.yml config | awk '/image:/ {print $2; exit}')" stat -c '%a' /var/lib/mysql) "${VOLUMES_DIR}/mysql_data"
		fi
		docker-compose -f $BASE_DIR/db.yml up -d --force-recreate
	elif [ "$INSTALL_MYSQL_SERVER" == "pull" ]; then
		docker-compose -f $BASE_DIR/db.yml pull
	fi
}

install_document_server () {
	reconfigure DOCUMENT_SERVER_JWT_HEADER ${DOCUMENT_SERVER_JWT_HEADER}
	reconfigure DOCUMENT_SERVER_JWT_SECRET ${DOCUMENT_SERVER_JWT_SECRET}
	if [[ -z ${DOCUMENT_SERVER_HOST} ]] && [ "$INSTALL_DOCUMENT_SERVER" == "true" ]; then
		docker-compose -f $BASE_DIR/ds.yml up -d
	elif [ "$INSTALL_DOCUMENT_SERVER" == "pull" ]; then
		docker-compose -f $BASE_DIR/ds.yml pull
	fi
}

install_rabbitmq () {
	if [[ -z ${RABBIT_HOST} ]] && [ "$INSTALL_RABBITMQ" == "true" ]; then
		docker-compose -f $BASE_DIR/rabbitmq.yml up -d
	elif [ "$INSTALL_RABBITMQ" == "pull" ]; then
		docker-compose -f $BASE_DIR/rabbitmq.yml pull
	fi
}

install_redis () {
	if [[ -z ${REDIS_HOST} ]] && [ "$INSTALL_REDIS" == "true" ]; then
		docker-compose -f $BASE_DIR/redis.yml up -d
	elif [ "$INSTALL_REDIS" == "pull" ]; then
		docker-compose -f $BASE_DIR/redis.yml pull
	fi
}

install_elasticsearch () {
	if [[ -z ${ELK_HOST} ]] && [ "$INSTALL_ELASTICSEARCH" == "true" ]; then
		if [ -n "${VOLUMES_DIR}" ]; then
			mkdir -p "${VOLUMES_DIR}/os_data"
			chown $(docker run --rm "$(docker-compose -f ${BASE_DIR}/opensearch.yml config | awk '/image:/ {print $2; exit}')" stat -c '%u:%g' /usr/share/opensearch/data) "${VOLUMES_DIR}/os_data"
		fi

		SAFE_MEMORY=$(( ( $(free --mega | grep -oP '\d+' | head -n 1) - 1024 ) / 2 )) # half of the remaining memory after the 1 GB reserve for the OS
		HEAP=$(( SAFE_MEMORY < 2048 ? 1 : SAFE_MEMORY < 4096 ? 2 : 4 ))  #if <2GB → 1GB; <4GB → 2GB; otherwise → 4GB
		sed -i "s/Xms[0-9]g/Xms${HEAP}g/g; s/Xmx[0-9]g/Xmx${HEAP}g/g" $BASE_DIR/opensearch.yml

		docker-compose -f $BASE_DIR/opensearch.yml up -d
	elif [ "$INSTALL_ELASTICSEARCH" == "pull" ]; then
		docker-compose -f $BASE_DIR/opensearch.yml pull
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
		
		docker-compose -f ${BASE_DIR}/fluent.yml -f ${BASE_DIR}/dashboards.yml up -d
	elif [ "$INSTALL_FLUENT_BIT" == "pull" ]; then
		docker-compose -f ${BASE_DIR}/fluent.yml -f ${BASE_DIR}/dashboards.yml pull
	fi
}

install_product () {
	if [ "$INSTALL_PRODUCT" == "true" ]; then
		if [ "${UPDATE}" = "true" ]; then
			LOCAL_CONTAINER_TAG="$(docker inspect --format='{{index .Config.Image}}' "${CONTAINER_NAME}" 2>/dev/null | awk -F':' '{print $2}';)"
			echo "Updating images from tag ${LOCAL_CONTAINER_TAG} to ${DOCKER_TAG}..."

			if [ "$LOCAL_CONTAINER_TAG" != "$DOCKER_TAG" ]; then
				if [ "$STACK_MODE" = "true" ]; then
					docker-compose -f $BASE_DIR/docspace-stack.yml -f $BASE_DIR/proxy.yml down
				else
					docker-compose "${COMPOSE_FILES[@]}" down
				fi
			fi
		fi

		reconfigure ENV_EXTENSION ${ENV_EXTENSION}
		reconfigure IDENTITY_PROFILE "${IDENTITY_PROFILE:-"prod,server"}"
		reconfigure APP_CORE_MACHINEKEY ${APP_CORE_MACHINEKEY}
		reconfigure IDENTITY_ENCRYPTION_SECRET ${IDENTITY_ENCRYPTION_SECRET}
		reconfigure APP_CORE_BASE_DOMAIN ${APP_CORE_BASE_DOMAIN}
		reconfigure APP_URL_PORTAL "${APP_URL_PORTAL:-"http://${PACKAGE_SYSNAME}-router:8092"}"
		reconfigure EXTERNAL_PORT ${EXTERNAL_PORT}

		if [[ -z ${MYSQL_HOST} ]] && [ "$INSTALL_MYSQL_SERVER" == "true" ] && [[ -n $(docker ps -q --filter "name=${PACKAGE_SYSNAME}-mysql-server") ]]; then
			echo -n "Waiting for MySQL container to become healthy..."
			(timeout 30 bash -c "while ! docker inspect --format '{{json .State.Health.Status }}' ${PACKAGE_SYSNAME}-mysql-server | grep -q 'healthy'; do sleep 1; done") && echo "OK" || (echo "FAILED")
		fi

		if [ "$STACK_MODE" = "true" ]; then
			docker-compose -f "$BASE_DIR/docspace-stack.yml" up -d
			docker-compose -f "$BASE_DIR/proxy.yml" up -d
		else
			docker-compose -f "$BASE_DIR/migration-runner.yml" up -d

			if [[ -n $(docker ps -q --filter "name=${PACKAGE_SYSNAME}-migration-runner") ]]; then
				echo -n "Waiting for database migration to complete..."
				timeout 30 bash -c "while [ $(docker wait ${PACKAGE_SYSNAME}-migration-runner) -ne 0 ]; do sleep 1; done;" && echo "OK" || echo "FAILED"
			fi

			docker-compose "${COMPOSE_FILES[@]}" up -d
		fi

		if [[ -n "${PREVIOUS_ELK_VERSION}" && "$(get_env_parameter "ELK_VERSION")" != "${PREVIOUS_ELK_VERSION}" ]]; then
			docker ps -q -f name=${PACKAGE_SYSNAME}-elasticsearch | xargs -r docker stop
			MYSQL_TAG=$(docker images --format "{{.Tag}}" mysql | head -n1)
			MYSQL_CONTAINER_NAME=$(get_env_parameter "MYSQL_CONTAINER_NAME" | sed "s/\${CONTAINER_PREFIX}/${PACKAGE_SYSNAME}-/g")
			docker run --rm --network="$(get_env_parameter "NETWORK_NAME")" mysql:${MYSQL_TAG:-latest} mysql -h "${MYSQL_HOST:-${MYSQL_CONTAINER_NAME}}" -P "${MYSQL_PORT:-3306}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE}" -e "TRUNCATE webstudio_index;"
		fi

		if [ ! -z "${CERTIFICATE_PATH}" ] && [[ ! -z "${APP_DOMAIN_PORTAL}" ]]; then
		    env ${DHPARAM_PATH:+DHPARAM_PATH="$DHPARAM_PATH"} \
			bash $BASE_DIR/config/${PRODUCT}-ssl-setup -f "${APP_DOMAIN_PORTAL}" "${CERTIFICATE_PATH}" "${CERTIFICATE_KEY_PATH}"
		elif [ ! -z "${LETS_ENCRYPT_DOMAIN}" ] && [ ! -z "${LETS_ENCRYPT_MAIL}" ]; then
		    env ${DHPARAM_PATH:+DHPARAM_PATH="$DHPARAM_PATH"} \
			bash $BASE_DIR/config/${PRODUCT}-ssl-setup "${LETS_ENCRYPT_MAIL}" "${LETS_ENCRYPT_DOMAIN}"
		elif [[ -n "${CERTIFICATE_KEY_PATH}${CERTIFICATE_PATH}${LETS_ENCRYPT_DOMAIN}${LETS_ENCRYPT_MAIL}" ]]; then
			echo -e "\e[31mERROR:\e[0m Missing required parameters for SSL setup"
			echo "Run 'bash $BASE_DIR/config/${PRODUCT}-ssl-setup --help' for usage information."
		fi

		#Fix for bug 70537 to ensure proper migration to version 3.0.0
		if [ "${UPDATE}" = "true" ] && [ -f "/etc/cron.weekly/${PRODUCT}-letsencrypt" ]; then
			bash $BASE_DIR/config/${PRODUCT}-ssl-setup -r
		fi
	elif [ "$INSTALL_PRODUCT" == "pull" ]; then
		docker-compose "${COMPOSE_FILES[@]}" pull
	fi
}

make_swap () {
	DISK_REQUIREMENTS=6144 #6Gb free space
	MEMORY_REQUIREMENTS=12000 #RAM ~12Gb

	AVAILABLE_DISK_SPACE=$(df -m /  | tail -1 | awk '{ print $4 }')
	TOTAL_MEMORY=$(free --mega | grep -oP '\d+' | head -n 1)
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
		echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
	fi
}

offline_check_docker_image() {
	[ ! -f "$1" ] && { echo "Error: File '$1' does not exist."; exit 1; }
	docker-compose -f "$1" config | grep -oP 'image:\s*\K\S+' | while IFS= read -r IMAGE_TAG; do
		docker images --format="{{.Repository}}:{{.Tag}}" "${IMAGE_TAG}"  | grep -q "${IMAGE_TAG%%:*}" || { echo "Error: The image '${IMAGE_TAG}' is not found in the local Docker registry."; kill -s TERM $PID; }
	done
}

check_registry_connection() {
	get_tag_from_registry ${IMAGE_NAME}
	[ -z "${TAGS_RESP[*]}" ] && { echo -e "Unable to download tags from ${REGISTRY_URL:-https://hub.docker.com}.\nTry specifying another docker registry URL using -reg"; exit 1; }
}

dependency_installation() {
	is_command_exists apt-get && apt-get -y update -qq

	install_package tar
	install_package curl
	install_package netstat net-tools

	if [ "${OFFLINE_INSTALLATION}" = "false" ]; then
		install_package dig  "dnsutils|bind-utils"
		install_package ping "iputils-ping|iputils"
		install_package ip   "iproute2|iproute"
	fi

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

	if ! is_command_exists docker-compose || [ $(docker-compose -v | awk '{sub(/^v/,"",$NF);split($NF,a,".");printf "%d%03d%03d",a[1],a[2],a[3]}') -lt 2018000 ]; then
		[ "${OFFLINE_INSTALLATION}" = "false" ] && install_docker_compose || { echo "docker-compose not installed or outdated version"; exit 1; }
	fi
}

check_docker_image () {
	reconfigure REGISTRY "${REGISTRY_URL:+$(sed -E 's~^https?://~~; s~/*$~~' <<< "$REGISTRY_URL")/}"
	reconfigure STATUS ${STATUS}
	reconfigure INSTALLATION_TYPE ${INSTALLATION_TYPE}
	reconfigure NETWORK_NAME ${NETWORK_NAME}
	reconfigure VOLUMES_DIR ${VOLUMES_DIR}
	reconfigure EXTRA_HOSTS ${EXTRA_HOSTS}
	
	reconfigure MYSQL_VERSION ${MYSQL_VERSION}
	reconfigure ELK_VERSION ${ELK_VERSION}
	reconfigure DOCUMENT_SERVER_IMAGE_NAME "${DOCUMENT_SERVER_IMAGE_NAME}:\${DOCUMENT_SERVER_VERSION}"
	reconfigure DOCUMENT_SERVER_VERSION ${DOCUMENT_SERVER_VERSION:-$(get_available_version "$DOCUMENT_SERVER_IMAGE_NAME")}

	DOCKER_TAG="${DOCKER_TAG:-$(get_available_version ${IMAGE_NAME})}"
	reconfigure DOCKER_TAG ${DOCKER_TAG}
	if [ "${OFFLINE_INSTALLATION}" != "false" ]; then
		[ "$INSTALL_RABBITMQ" == "true" ]           && offline_check_docker_image ${BASE_DIR}/db.yml
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
}

services_check_connection () {
	# Fixes issues with variables when upgrading to v1.1.3
	HOSTS=("ELK_HOST" "REDIS_HOST" "RABBIT_HOST" "MYSQL_HOST")
	for HOST in "${HOSTS[@]}"; do [[ "${!HOST}" == *CONTAINER_PREFIX* || "${!HOST}" == *$PACKAGE_SYSNAME* ]] && export "$HOST="; done
	[[ "${APP_URL_PORTAL}" == *${PACKAGE_SYSNAME}-proxy* ]] && APP_URL_PORTAL=""

	if [[ ! -z "$MYSQL_HOST" ]]; then
		establish_conn ${MYSQL_HOST} "${MYSQL_PORT:-3306}" "MySQL"
		reconfigure MYSQL_HOST ${MYSQL_HOST}
		reconfigure MYSQL_PORT "${MYSQL_PORT:-3306}"
	fi
	if [[ ! -z "$DOCUMENT_SERVER_HOST" ]]; then
		APP_URL_PORTAL=${APP_URL_PORTAL:-"http://$(curl -s -4 ifconfig.me):${EXTERNAL_PORT}"}
		establish_conn ${DOCUMENT_SERVER_HOST} ${DOCUMENT_SERVER_PORT} "${PACKAGE_SYSNAME^^} Docs"
		reconfigure DOCUMENT_SERVER_URL_EXTERNAL ${DOCUMENT_SERVER_URL_EXTERNAL}
		reconfigure DOCUMENT_SERVER_URL_PUBLIC ${DOCUMENT_SERVER_URL_EXTERNAL}
	fi
	if [[ ! -z "$RABBIT_HOST" ]]; then
		establish_conn ${RABBIT_HOST} "${RABBIT_PORT:-5672}" "RabbitMQ"
		reconfigure RABBIT_PROTOCOL ${RABBIT_PROTOCOL:-amqp}
		reconfigure RABBIT_HOST ${RABBIT_HOST}
		reconfigure RABBIT_PORT "${RABBIT_PORT:-5672}"
		reconfigure RABBIT_USER_NAME ${RABBIT_USER_NAME}
		reconfigure RABBIT_PASSWORD ${RABBIT_PASSWORD}
		reconfigure RABBIT_VIRTUAL_HOST "${RABBIT_VIRTUAL_HOST:-/}"
	fi
	if [[ ! -z "$REDIS_HOST" ]]; then
		establish_conn ${REDIS_HOST} "${REDIS_PORT:-6379}" "Redis"
		reconfigure REDIS_HOST ${REDIS_HOST}
		reconfigure REDIS_PORT "${REDIS_PORT:-6379}"
		reconfigure REDIS_USER_NAME ${REDIS_USER_NAME}
		reconfigure REDIS_PASSWORD ${REDIS_PASSWORD}
	fi
	if [[ ! -z "$ELK_HOST" ]]; then
		establish_conn ${ELK_HOST} "${ELK_PORT:-9200}" "search engine"
		reconfigure ELK_SCHEME "${ELK_SCHEME:-http}"
		reconfigure ELK_HOST ${ELK_HOST}
		reconfigure ELK_PORT "${ELK_PORT:-9200}"
	fi
}

start_installation () {
	root_checking

	set_installation_type_data

	get_os_info
	check_os_info
	check_kernel

	dependency_installation

	if [ "$UPDATE" != "true" ]; then
		check_ports
	fi

	if [ "$SKIP_HARDWARE_CHECK" != "true" ]; then
		check_hardware
	fi

	if [ "$MAKESWAP" == "true" ]; then
		make_swap
	fi

	docker_login

	[ "${OFFLINE_INSTALLATION}" = "false" ] && check_registry_connection

	create_network

	[ "${OFFLINE_INSTALLATION}" = "false" ] && domain_check

	if [ "$UPDATE" = "true" ]; then
		set_docspace_params
	fi

	set_docs_url_external
	set_jwt_secret
	set_jwt_header

	set_secrets

	set_mysql_params

	download_files

	check_docker_image

	services_check_connection

	install_elasticsearch

	install_fluent_bit

	install_mysql_server

	install_rabbitmq

	install_redis

	install_document_server

	install_product

	echo ""
	echo "Thank you for installing ${PACKAGE_SYSNAME^^} ${PRODUCT_NAME}."
	echo "In case you have any questions contact us via http://support.${PACKAGE_SYSNAME}.com or visit our forum at http://forum.${PACKAGE_SYSNAME}.com"
	echo ""

	exit 0
}

[[ $UNINSTALL != true ]] && start_installation || uninstall
