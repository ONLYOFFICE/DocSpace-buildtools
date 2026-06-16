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


set -e

package_manager="yum"
package_sysname="onlyoffice"
product_name="DocSpace"
product=$(tr '[:upper:]' '[:lower:]' <<< ${product_name})
INSTALLATION_TYPE="ENTERPRISE"
MAKESWAP="true"
RES_APP_INSTALLED="is already installed"
RES_CHECK_PORTS="Please make sure that the ports are free."
RES_INSTALL_SUCCESS="Thank you for installing ONLYOFFICE ${product_name}."
RES_QUESTIONS="In case you have any questions contact us via http://support.onlyoffice.com or visit our forum at http://forum.onlyoffice.com"
RES_MARIADB="To continue the installation, you need to remove MariaDB"
INSTALL_FLUENT_BIT="true"

while [ "$1" != "" ]; do
	case $1 in
        -u | --update )                     [ -n "$2" ] && UPDATE=$2 && shift ;;
        -uni | --uninstall )                [ -n "$2" ] && UNINSTALL=$2 && shift ;;
        -je | --jwtenabled )                [ -n "$2" ] && JWT_ENABLED=$2 && shift ;;
        -jh | --jwtheader )                 [ -n "$2" ] && JWT_HEADER=$2 && shift ;;
        -js | --jwtsecret )                 [ -n "$2" ] && JWT_SECRET=$2 && shift ;;
        -gb | --gitbranch )                 [ -n "$2" ] && GIT_BRANCH=$2 && shift ;;
        -ifb | --installfluentbit )         [ -n "$2" ] && INSTALL_FLUENT_BIT=$2 && shift ;;
        -dsv | --docspaceversion )          [ -n "$2" ] && PRODUCT_VERSION=$2 && shift ;;
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

DOWNLOAD_URL_PREFIX="https://download.onlyoffice.com/${product}"
[ -n "$GIT_BRANCH" ] && DOWNLOAD_URL_PREFIX="https://raw.githubusercontent.com/ONLYOFFICE/${product}-buildtools/${GIT_BRANCH}/install/OneClickInstall"

# Run uninstall if requested
if [ "${UNINSTALL}" == "true" ]; then
    if [ "${LOCAL_SCRIPTS}" == "true" ]; then
        source install-RedHat/uninstall.sh
    else
        source <(curl -fsSL "${DOWNLOAD_URL_PREFIX}"/install-RedHat/uninstall.sh)
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
	source common/check-ports.sh
	source install-RedHat/install-preq.sh
	source install-RedHat/install-app.sh
else
	source <(curl -sS "${DOWNLOAD_URL_PREFIX}"/install-RedHat/tools.sh)
	source <(curl -sS "${DOWNLOAD_URL_PREFIX}"/common/check-ports.sh)
	source <(curl -sS "${DOWNLOAD_URL_PREFIX}"/install-RedHat/install-preq.sh)
	source <(curl -sS "${DOWNLOAD_URL_PREFIX}"/install-RedHat/install-app.sh)
fi
