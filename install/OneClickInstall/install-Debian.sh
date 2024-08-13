#!/bin/bash

set -e

package_sysname="onlyoffice";
DS_COMMON_NAME="onlyoffice";
product_name="DocSpace"
product=$(tr '[:upper:]' '[:lower:]' <<< ${product_name})
INSTALLATION_TYPE="ENTERPRISE"
MAKESWAP="true"
RES_APP_INSTALLED="is already installed";
RES_APP_CHECK_PORTS="uses ports"
RES_CHECK_PORTS="please, make sure that the ports are free.";
RES_INSTALL_SUCCESS="Thank you for installing ONLYOFFICE ${product_name}.";
RES_QUESTIONS="In case you have any questions contact us via http://support.onlyoffice.com or visit our forum at http://forum.onlyoffice.com"
INSTALL_FLUENT_BIT="true"

while [ "$1" != "" ]; do
	case $1 in
		-je     | --jwtenabled         ) [ -n "$2" ]                           && DS_JWT_ENABLED=$2        && shift ;;
		-jh     | --jwtheader          ) [ -n "$2" ]                           && DS_JWT_HEADER=$2         && shift ;;
		-js     | --jwtsecret          ) [ -n "$2" ]                           && DS_JWT_SECRET=$2         && shift ;;
		-gb     | --gitbranch          ) [ -n "$2" ]                           && GIT_BRANCH=$2            && shift ;;
		-du     | --dashboadrsusername ) [ -n "$2" ]                           && DASHBOARDS_USERNAME=$2   && shift ;;
		-dp     | --dashboadrspassword ) [ -n "$2" ]                           && DASHBOARDS_PASSWORD=$2   && shift ;;
		-it     | --installation_type  ) [ -n "$2" ]                           && INSTALLATION_TYPE=${2^^} && shift ;;
		-u      | --update             ) [ "$2" == "true" -o "$2" == "false" ] && UPDATE=$2                && shift ;;
		-ifb    | --installfluentbit   ) [ "$2" == "true" -o "$2" == "false" ] && INSTALL_FLUENT_BIT=$2    && shift ;;
		-ls     | --localscripts       ) [ "$2" == "true" -o "$2" == "false" ] && LOCAL_SCRIPTS=$2         && shift ;;
		-skiphc | --skiphardwarecheck  ) [ "$2" == "true" -o "$2" == "false" ] && SKIP_HARDWARE_CHECK=$2   && shift ;;
		-ms     | --makeswap           ) [ "$2" == "true" -o "$2" == "false" ] && MAKESWAP=$2              && shift ;;
		-?      | -h        | --help   )
			echo "  Usage $0 [PARAMETER] [[PARAMETER], ...]"
			echo "    Parameters:"
			echo "      -it, --installation_type          installation type (community|enterprise)"
			echo "      -u, --update                      use to update existing components (true|false)"
			echo "      -je, --jwtenabled                 specifies the enabling the JWT validation (true|false)"
			echo "      -jh, --jwtheader                  defines the http header that will be used to send the JWT"
			echo "      -js, --jwtsecret                  defines the secret key to validate the JWT in the request"
			echo "      -ifb, --installfluentbit          install or update fluent-bit (true|false)"
			echo "      -du, --dashboadrsusername         login for authorization in /dashboards/"
			echo "      -dp, --dashboadrspassword         password for authorization in /dashboards/"
			echo "      -ls, --local_scripts              use 'true' to run local scripts (true|false)"
			echo "      -skiphc, --skiphardwarecheck      use to skip hardware check (true|false)"
			echo "      -ms, --makeswap                   make swap file (true|false)"
			echo "      -?, -h, --help                    this help"
			echo
			exit 0
		;;
	esac
	shift
done

UPDATE="${UPDATE:-false}"
LOCAL_SCRIPTS="${LOCAL_SCRIPTS:-false}"
SKIP_HARDWARE_CHECK="${SKIP_HARDWARE_CHECK:-false}"

apt-get update -y --allow-releaseinfo-change;
dpkg -l | grep -q "^ii  curl" || apt-get install -yq curl

DOWNLOAD_URL_PREFIX="https://download.${product_sysname}.com/${product}/install-Debian"
[ -n "$GIT_BRANCH" ] && DOWNLOAD_URL_PREFIX="https://raw.githubusercontent.com/${product_sysname^^}/${product}-buildtools/${GIT_BRANCH}/install/OneClickInstall/install-Debian"

[[ "${LOCAL_SCRIPTS}" == "true" ]] && source install-Debian/bootstrap.sh || source <(curl ${DOWNLOAD_URL_PREFIX}/bootstrap.sh)

# add onlyoffice repo
mkdir -p -m 700 $HOME/.gnupg
echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] http://download.onlyoffice.com/repo/debian squeeze main" | tee /etc/apt/sources.list.d/onlyoffice.list
curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/onlyoffice.gpg --import
chmod 644 /usr/share/keyrings/onlyoffice.gpg

declare -x LANG="en_US.UTF-8"
declare -x LANGUAGE="en_US:en"
declare -x LC_ALL="en_US.UTF-8"

if [ "${LOCAL_SCRIPTS}" == "true" ]; then
	source install-Debian/tools.sh
	source install-Debian/check-ports.sh
	source install-Debian/install-preq.sh
	source install-Debian/install-app.sh
else
	source <(curl ${DOWNLOAD_URL_PREFIX}/tools.sh)
	source <(curl ${DOWNLOAD_URL_PREFIX}/check-ports.sh)
	source <(curl ${DOWNLOAD_URL_PREFIX}/install-preq.sh)
	source <(curl ${DOWNLOAD_URL_PREFIX}/install-app.sh)
fi
