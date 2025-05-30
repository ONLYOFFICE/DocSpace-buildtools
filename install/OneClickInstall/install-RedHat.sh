#!/bin/bash

set -e

package_manager="yum"
package_sysname="onlyoffice"
product_name="DocSpace"
product=$(tr '[:upper:]' '[:lower:]' <<< ${product_name})
INSTALLATION_TYPE="ENTERPRISE"
MAKESWAP="true"
RES_APP_INSTALLED="is already installed"
RES_APP_CHECK_PORTS="uses ports"
RES_CHECK_PORTS="please, make sure that the ports are free."
RES_INSTALL_SUCCESS="Thank you for installing ONLYOFFICE ${product_name}."
RES_QUESTIONS="In case you have any questions contact us via http://support.onlyoffice.com or visit our forum at http://forum.onlyoffice.com"
RES_MARIADB="To continue the installation, you need to remove MariaDB"
INSTALL_FLUENT_BIT="true"

while [ "$1" != "" ]; do
	case $1 in

		-u | --update )
			if [ "$2" != "" ]; then
				UPDATE=$2
				shift
			fi
		;;

		-uni | --uninstall )
			if [ "$2" != "" ]; then
				UNINSTALL=$2
				shift
			fi
		;;

		-je | --jwtenabled )
			if [ "$2" != "" ]; then
				JWT_ENABLED=$2
				shift
			fi
		;;

		-jh | --jwtheader )
			if [ "$2" != "" ]; then
				JWT_HEADER=$2
				shift
			fi
		;;

		-js | --jwtsecret )
			if [ "$2" != "" ]; then
				JWT_SECRET=$2
				shift
			fi
		;;
		
		-gb | --gitbranch )
			if [ "$2" != "" ]; then
				PARAMETERS="$PARAMETERS ${1}"
				GIT_BRANCH=$2
				shift
			fi
		;;
		
		-ifb | --installfluentbit )
			if [ "$2" != "" ]; then
				INSTALL_FLUENT_BIT=$2
				shift
			fi
		;;

		-du | --dashboardsusername )
			if [ "$2" != "" ]; then
				DASHBOARDS_USERNAME=$2
				shift
			fi
		;;

		-dp | --dashboardspassword )
			if [ "$2" != "" ]; then
				DASHBOARDS_PASSWORD=$2
				shift
			fi
		;;

		-ls | --localscripts )
			if [ "$2" != "" ]; then
				LOCAL_SCRIPTS=$2
				shift
			fi
		;;

		-skiphc | --skiphardwarecheck )
			if [ "$2" != "" ]; then
				SKIP_HARDWARE_CHECK=$2
				shift
			fi
		;;

		-it | --installation_type )
			if [ "$2" != "" ]; then
				INSTALLATION_TYPE="${2^^}"
				shift
			fi
		;;
		
		-ms | --makeswap )
			if [ "$2" != "" ]; then
				MAKESWAP=$2
				shift
			fi
		;;

		-h | -? | --help )
			echo "  Usage $0 [PARAMETER] [[PARAMETER], ...]"
			echo "    Parameters:"
			echo "      -it, --installation_type          installation type (community|developer|enterprise)"
			echo "      -u, --update                      use to update existing components (true|false)"
			echo "      -uni, --uninstall                 uninstall existing installation (true|false)"
			echo "      -je, --jwtenabled                 specifies the enabling the JWT validation (true|false)"
			echo "      -jh, --jwtheader                  defines the http header that will be used to send the JWT"
			echo "      -js, --jwtsecret                  defines the secret key to validate the JWT in the request"
			echo "      -ifb, --installfluentbit          install or update fluent-bit (true|false)"
			echo "      -du, --dashboardsusername         login for authorization in /dashboards/"
			echo "      -dp, --dashboardspassword         password for authorization in /dashboards/"
			echo "      -ls, --localscripts               use 'true' to run local scripts (true|false)"
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

DOWNLOAD_URL_PREFIX="https://download.onlyoffice.com/${product}/install-RedHat"
[ -n "$GIT_BRANCH" ] && DOWNLOAD_URL_PREFIX="https://raw.githubusercontent.com/ONLYOFFICE/${product}-buildtools/${GIT_BRANCH}/install/OneClickInstall/install-RedHat"

# Run uninstall if requested
if [ "${UNINSTALL}" == "true" ]; then
    if [ "${LOCAL_SCRIPTS}" == "true" ]; then
        source install-RedHat/uninstall.sh
    else
        source <(curl -fsSL "${DOWNLOAD_URL_PREFIX}"/uninstall.sh)
    fi
    exit 0
fi

cat > /etc/yum.repos.d/onlyoffice.repo <<END
[onlyoffice]
name=onlyoffice repo
baseurl=http://download.onlyoffice.com/repo/centos/main/noarch/
gpgcheck=1
enabled=1
gpgkey=https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE
END

if [ "$LOCAL_SCRIPTS" = "true" ]; then
	source install-RedHat/tools.sh
	source install-RedHat/bootstrap.sh
	source install-RedHat/check-ports.sh
	source install-RedHat/install-preq.sh
	source install-RedHat/install-app.sh
else
	source <(curl "${DOWNLOAD_URL_PREFIX}"/tools.sh)
	source <(curl "${DOWNLOAD_URL_PREFIX}"/bootstrap.sh)
	source <(curl "${DOWNLOAD_URL_PREFIX}"/check-ports.sh)
	source <(curl "${DOWNLOAD_URL_PREFIX}"/install-preq.sh)
	source <(curl "${DOWNLOAD_URL_PREFIX}"/install-app.sh)
fi
