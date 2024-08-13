#!/bin/bash

set -e

package_manager="yum"
package_sysname="onlyoffice";
product_name="DocSpace"
product=$(tr '[:upper:]' '[:lower:]' <<< ${product_name})
INSTALLATION_TYPE="ENTERPRISE"
MAKESWAP="true"
RES_APP_INSTALLED="is already installed";
RES_APP_CHECK_PORTS="uses ports"
RES_CHECK_PORTS="please, make sure that the ports are free.";
RES_INSTALL_SUCCESS="Thank you for installing ONLYOFFICE ${product_name}.";
RES_QUESTIONS="In case you have any questions contact us via http://support.onlyoffice.com or visit our forum at http://forum.onlyoffice.com"
RES_MARIADB="To continue the installation, you need to remove MariaDB"
INSTALL_FLUENT_BIT="true"

res_unsupported_version () {
	RES_CHOICE="Please, enter Y or N"
	RES_CHOICE_INSTALLATION="Continue installation [Y/N]? "
	RES_UNSPPORTED_VERSION="You have an unsupported version of $DIST installed"
	RES_SELECT_INSTALLATION="Select 'N' to cancel the ONLYOFFICE installation (recommended). Select 'Y' to continue installing ONLYOFFICE"
	RES_ERROR_REMINDER="Please note, that if you continue with the installation, there may be errors"
}

while [ "$1" != "" ]; do
	case $1 in
		-je     | --jwtenabled         ) [ -n "$2" ]                           && JWT_ENABLED=$2           && shift ;;
		-jh     | --jwtheader          ) [ -n "$2" ]                           && JWT_HEADER=$2            && shift ;;
		-js     | --jwtsecret          ) [ -n "$2" ]                           && JWT_SECRET=$2            && shift ;;
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

cat > /etc/yum.repos.d/onlyoffice.repo <<END
[onlyoffice]
name=onlyoffice repo
baseurl=http://download.onlyoffice.com/repo/centos/main/noarch/
gpgcheck=1
enabled=1
gpgkey=https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE
END

DOWNLOAD_URL_PREFIX="https://download.${product_sysname}.com/${product}/install-RedHat"
[ -n "$GIT_BRANCH" ] && DOWNLOAD_URL_PREFIX="https://raw.githubusercontent.com/${product_sysname^^}/${product}-buildtools/${GIT_BRANCH}/install/OneClickInstall/install-RedHat"

if [ "$LOCAL_SCRIPTS" = "true" ]; then
	source install-RedHat/tools.sh
	source install-RedHat/bootstrap.sh
	source install-RedHat/check-ports.sh
	source install-RedHat/install-preq.sh
	source install-RedHat/install-app.sh
else
	source <(curl ${DOWNLOAD_URL_PREFIX}/tools.sh)
	source <(curl ${DOWNLOAD_URL_PREFIX}/bootstrap.sh)
	source <(curl ${DOWNLOAD_URL_PREFIX}/check-ports.sh)
	source <(curl ${DOWNLOAD_URL_PREFIX}/install-preq.sh)
	source <(curl ${DOWNLOAD_URL_PREFIX}/install-app.sh)
fi
