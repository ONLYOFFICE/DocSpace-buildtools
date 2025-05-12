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

PARAMETERS="$PARAMETERS -it COMMUNITY"
DOCKER=""
LOCAL_SCRIPTS="false"
product="docspace"
product_sysname="onlyoffice"
FILE_NAME="$(basename "$0")"
ENABLE_LOGGING="true"

while [ "$1" != "" ]; do
	case $1 in
		-ls | --localscripts )
			if [ "$2" == "true" ] || [ "$2" == "false" ]; then
				PARAMETERS="$PARAMETERS ${1}"
				LOCAL_SCRIPTS=$2
				shift
			fi
		;;
		
		-log | --logging )
			if [ "$2" == "true" ] || [ "$2" == "false" ]; then
				ENABLE_LOGGING=$2
				shift 2
			fi
		;;
		
		-gb | --gitbranch )
			if [ "$2" != "" ]; then
				PARAMETERS="$PARAMETERS ${1}"
				GIT_BRANCH=$2
				shift
			fi
		;;

		docker )
			DOCKER="true"
			shift && continue
		;;

		package )
			DOCKER="false"
			shift && continue
		;;

		"-?" | -h | --help )
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

if is_command_exists docker && docker ps -a --format '{{.Names}}' | grep -q "${product_sysname}-api"; then
    DOCKER="true"
    PARAMETERS="-u true $PARAMETERS"
elif (is_command_exists dpkg && dpkg -s ${product}-api >/dev/null 2>&1) || (is_command_exists rpm && rpm -q ${product}-api >/dev/null 2>&1); then
    DOCKER="false"
	PARAMETERS="-u true $PARAMETERS"
fi
 
[ -z "$DOCKER" ] && read_installation_method

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
    LOG_FILE="OneClick${SCRIPT_NAME%.sh}_$(date +%Y%m%d_%H%M%S).log"
    touch "${LOG_FILE}" || { echo "Failed to create log file"; exit 1; }
    script -q -e "${LOG_FILE}" -c "bash ${SCRIPT_NAME} ${PARAMETERS}"
    EXIT_CODE=${PIPESTATUS[0]}
else
    bash ${SCRIPT_NAME} ${PARAMETERS} || EXIT_CODE=$?
fi

[ "$LOCAL_SCRIPTS" != "true" ] && rm ${SCRIPT_NAME}
[ "$ENABLE_LOGGING" = "true" ] && [ ${EXIT_CODE:-0} -eq 0 ] && rm "${LOG_FILE}"

exit ${EXIT_CODE:-0}
