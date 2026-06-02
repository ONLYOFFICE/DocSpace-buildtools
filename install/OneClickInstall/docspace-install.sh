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

PARAMETERS="$PARAMETERS -it COMMUNITY"
DOCKER=""
LOCAL_SCRIPTS="false"
product="docspace"
product_sysname="onlyoffice"
FILE_NAME="$(basename "$0")"
ENABLE_LOGGING="true"

while [ "$1" != "" ]; do
	case $1 in
        -ls | --localscripts )     [[ "$2" == "true" || "$2" == "false" ]] && PARAMETERS="$PARAMETERS ${1}" && LOCAL_SCRIPTS=$2 && shift ;;
        -log | --logging )         [[ "$2" == "true" || "$2" == "false" ]] && ENABLE_LOGGING=$2 && shift 2 && continue ;;
        -gb | --gitbranch )        [ -n "$2" ] && PARAMETERS="$PARAMETERS ${1}" && GIT_BRANCH=$2 && shift ;;
        -dsv | --docspaceversion ) [ -n "$2" ] && PARAMETERS="$PARAMETERS ${1}" && DOCKER_TAG=$2 && PRODUCT_VERSION=$2 && shift ;;
        docker ) DOCKER="true"; shift ; continue ;;
        package ) DOCKER="false"; shift ; continue ;;
        -h | -? | --help )
            if [ -z "$DOCKER" ]; then
                echo "Run 'bash $FILE_NAME docker' to install Docker version of application."
                echo "Run 'bash $FILE_NAME package' to install DEB/RPM version."
                echo "Run 'bash $FILE_NAME docker -h' or 'bash $FILE_NAME package -h' to get more details."
                exit 0
            fi
            PARAMETERS="$PARAMETERS -ht $FILE_NAME"
        ;;
    esac

	PARAMETERS="$PARAMETERS ${1}"
	shift
done

root_checking () {
	[[ $EUID -eq 0 ]] || { echo "To perform this action you must be logged in with root rights"; exit 1; }
}

is_command_exists () {
	type "$1" &> /dev/null
}

install_curl () {
	if is_command_exists apt-get; then
		apt-get -y update
		apt-get -y -q install curl
	elif is_command_exists yum; then
		yum -y install curl
	fi

	is_command_exists curl || { echo "Command curl not found."; exit 1; }
}

read_installation_method() {
    echo "Select 'Y' to install ${product_sysname^^} $product using Docker (recommended)."
    echo "Select 'N' to install it using RPM/DEB packages."
    while true; do
        read -p "Install with Docker [Y/N/C]? " choice
        case "$choice" in
            [yY]) DOCKER="true"; break ;;
            [nN]) DOCKER="false"; break ;;
            [cC]) exit 0 ;;
            *) echo "Please, enter Y, N, or C to cancel." ;;
        esac
    done
}

root_checking

is_command_exists curl || install_curl

if is_command_exists docker && docker ps -a --format '{{.Names}}' | grep -qE "${product_sysname}-api|${product_sysname}-dotnet-services"; then
    DOCKER="true"
    PARAMETERS="-u true $PARAMETERS"
elif (is_command_exists dpkg && dpkg -s ${product}-api >/dev/null 2>&1) || (is_command_exists rpm && rpm -q ${product}-api >/dev/null 2>&1); then
    DOCKER="false"
	PARAMETERS="-u true $PARAMETERS"
fi
 
[ -z "$DOCKER" ] && read_installation_method

# Auto-detect legacy installs
if [[ "${DOCKER}" == "true" ]] && [[ ${DOCKER_TAG} =~ ^([0-9]+\.[0-9]+\.[0-9]+)(\.[0-9]+)?$ ]]; then
  TAG="v${BASH_REMATCH[1]}"; LATEST_TAG=$(curl -s "https://api.github.com/repos/${product_sysname^^}/${product}/releases/latest" | grep -Po '"tag_name":\s*"\K[^"]+')
  if [[ "${TAG}" != "${LATEST_TAG}" ]] && curl -sfI "https://github.com/${product_sysname^^}/${product}-buildtools/releases/tag/${TAG}-server" >/dev/null; then
	>&2 echo "Warning: legacy install detected (v${BASH_REMATCH[1]}) — compatibility issues or unforeseen errors may occur."
    PARAMETERS="${PARAMETERS} -gb ${TAG}-server"; GIT_BRANCH="${TAG}-server"
  fi
fi

DOWNLOAD_URL_PREFIX="https://download.${product_sysname}.com/${product}"
[ -n "$GIT_BRANCH" ] && DOWNLOAD_URL_PREFIX="https://raw.githubusercontent.com/${product_sysname^^}/${product}-buildtools/${GIT_BRANCH}/install/OneClickInstall"

if [ "$DOCKER" == "true" ]; then
    SCRIPT_NAME="install-Docker.sh"
elif [ -f /etc/redhat-release ]; then
    SCRIPT_NAME="install-RedHat.sh"
elif [ -f /etc/debian_version ]; then
    SCRIPT_NAME="install-Debian.sh"
else
    echo "Not supported OS"
    exit 1
fi

[ "$LOCAL_SCRIPTS" != "true" ] && curl -s -O ${DOWNLOAD_URL_PREFIX}/${SCRIPT_NAME}

if [ "$ENABLE_LOGGING" = "true" ]; then
    command -v script >/dev/null 2>&1 || { command -v dnf >/dev/null 2>&1 && dnf -y install util-linux-script; }
    if command -v script >/dev/null 2>&1; then
        LOG_FILE="OneClick${SCRIPT_NAME%.sh}_$(date +%Y%m%d_%H%M%S).log"
        touch "${LOG_FILE}" || { echo "Failed to create log file"; exit 1; }
        script -q -e "${LOG_FILE}" -c "bash ${SCRIPT_NAME} ${PARAMETERS}"
        EXIT_CODE=${PIPESTATUS[0]}
    else
        bash ${SCRIPT_NAME} ${PARAMETERS} || EXIT_CODE=$?
    fi
else
    bash ${SCRIPT_NAME} ${PARAMETERS} || EXIT_CODE=$?
fi

[ "$LOCAL_SCRIPTS" != "true" ] && rm ${SCRIPT_NAME}
[ "$ENABLE_LOGGING" = "true" ] && { [ "${EXIT_CODE:-0}" -eq 0 ] && rm -f "$LOG_FILE" || echo -e "\033[0;31mAn error occurred while executing the script. Log saved to: $LOG_FILE\033[0m"; }

exit ${EXIT_CODE:-0}
