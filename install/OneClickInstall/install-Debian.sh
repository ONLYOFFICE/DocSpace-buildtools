#!/bin/bash

set -e

package_sysname="onlyoffice"
DS_COMMON_NAME="onlyoffice"
product_name="DocSpace"
product=$(tr '[:upper:]' '[:lower:]' <<< ${product_name})
INSTALLATION_TYPE="ENTERPRISE"
MAKESWAP="true"
RES_APP_INSTALLED="is already installed"
RES_APP_CHECK_PORTS="Application uses the following ports"
RES_CHECK_PORTS="Please make sure that the ports are free."
RES_INSTALL_SUCCESS="Thank you for installing ONLYOFFICE ${product_name}."
RES_QUESTIONS="In case you have any questions contact us via http://support.onlyoffice.com or visit our forum at http://forum.onlyoffice.com"
INSTALL_FLUENT_BIT="true"

while [ "$1" != "" ]; do
	case $1 in
        -u | --update )                     [ -n "$2" ] && UPDATE=$2 && shift ;;
        -uni | --uninstall )                [ -n "$2" ] && UNINSTALL=$2 && shift ;;
        -je | --jwtenabled )                [ -n "$2" ] && DS_JWT_ENABLED=$2 && shift ;;
        -jh | --jwtheader )                 [ -n "$2" ] && DS_JWT_HEADER=$2 && shift ;;
        -js | --jwtsecret )                 [ -n "$2" ] && DS_JWT_SECRET=$2 && shift ;;
        -gb | --gitbranch )                 [ -n "$2" ] && PARAMETERS="$PARAMETERS ${1}" && GIT_BRANCH=$2 && shift ;;
        -ifb | --installfluentbit )         [ -n "$2" ] && INSTALL_FLUENT_BIT=$2 && shift ;;
        -du | --dashboardsusername )        [ -n "$2" ] && DASHBOARDS_USERNAME=$2 && shift ;;
        -dp | --dashboardspassword )        [ -n "$2" ] && DASHBOARDS_PASSWORD=$2 && shift ;;
        -ls | --localscripts )              [ -n "$2" ] && LOCAL_SCRIPTS=$2 && shift ;;
        -skiphc | --skiphardwarecheck )     [ -n "$2" ] && SKIP_HARDWARE_CHECK=$2 && shift ;;
        -it | --installationtype | --installation_type ) [ -n "$2" ] && INSTALLATION_TYPE="${2^^}" && shift ;;
        -ms | --makeswap )                  [ -n "$2" ] && MAKESWAP=$2 && shift ;;
        -h | -? | --help )
            echo "  Usage $0 [PARAMETER] [[PARAMETER], ...]"
            echo "    Parameters:"
            echo "      -it, --installationtype           installation type (community|developer|enterprise)"
            echo "      -u, --update                      use to update existing components (true|false)"
            echo "      -uni, --uninstall                 uninstall existing installation (true|false)"
            echo "      -je, --jwtenabled                 specifies whether JWT validation is enabled (true|false)"
            echo "      -jh, --jwtheader                  defines the HTTP header that will be used to send the JWT"
            echo "      -js, --jwtsecret                  defines the secret key to validate the JWT in the request"
            echo "      -ifb, --installfluentbit          install or update fluent-bit (true|false)"
            echo "      -du, --dashboardsusername         username for authorization in /dashboards/"
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

if fuser /var/lib/dpkg/lock-frontend1 &>/dev/null; then
  echo "Waiting for /var/lib/dpkg/lock-frontend1 to be released (up to 60 seconds)..."
   timeout 60 bash -c 'while fuser /var/lib/dpkg/lock-frontend1 &>/dev/null; do sleep 1; done'
fi

apt-get update -y --allow-releaseinfo-change;
if [ "$(dpkg-query -W -f='${Status}' curl 2>/dev/null | grep -c "ok installed")" -eq 0 ]; then
  apt-get install -yq curl
fi

DOWNLOAD_URL_PREFIX="https://download.onlyoffice.com/${product}/install-Debian"
[ -n "$GIT_BRANCH" ] && DOWNLOAD_URL_PREFIX="https://raw.githubusercontent.com/ONLYOFFICE/${product}-buildtools/${GIT_BRANCH}/install/OneClickInstall/install-Debian"

# Run uninstall if requested
if [ "${UNINSTALL}" == "true" ]; then
    if [ "${LOCAL_SCRIPTS}" == "true" ]; then
        source install-Debian/uninstall.sh
    else
        source <(curl -fsSL "${DOWNLOAD_URL_PREFIX}"/uninstall.sh)
    fi
    exit 0
fi

if [ "${LOCAL_SCRIPTS}" == "true" ]; then
	source install-Debian/bootstrap.sh
else
	source <(curl -sS ${DOWNLOAD_URL_PREFIX}/bootstrap.sh)
fi

# add onlyoffice repo
mkdir -p "$HOME/.gnupg" && chmod 700 "$HOME/.gnupg"
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
	source <(curl -sS "${DOWNLOAD_URL_PREFIX}"/tools.sh)
	source <(curl -sS "${DOWNLOAD_URL_PREFIX}"/check-ports.sh)
	source <(curl -sS "${DOWNLOAD_URL_PREFIX}"/install-preq.sh)
	source <(curl -sS "${DOWNLOAD_URL_PREFIX}"/install-app.sh)
fi
