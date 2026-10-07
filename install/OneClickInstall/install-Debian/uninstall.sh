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

echo "
#######################################
#  UNINSTALL ${product_name}
#######################################
"

# Ask to uninstall dependencies
read -r -p "Uninstall all dependencies (mysql, opensearch and others)? (Y/n): " DEP_CHOICE
DEP_CHOICE=${DEP_CHOICE,,}

if [[ "$DEP_CHOICE" =~ ^(y|yes|)$ ]]; then
    UNINSTALL_DEPENDENCIES=true
fi

# Get Apps packages to uninstall
mapfile -t PACKAGES_TO_UNINSTALL < <(dpkg -l | awk '{print $2}' | grep -E "^(${package}|${legacy_product})(-|:|$)" || true)

KEEP_DOCS=false
mapfile -t DOCUMENT_SERVER_PACKAGES < <(dpkg -l | awk '$1 ~ /^.i/{print $2}' | grep -E "^${package_sysname}-documentserver(-de|-ee)?(:|$)" || true)
if [ "${#DOCUMENT_SERVER_PACKAGES[@]}" -gt 0 ]; then
    read -r -p "Also uninstall ${package_sysname^^} Docs? (y/N): " DOCS_CHOICE || DOCS_CHOICE=""
    if [[ "${DOCS_CHOICE,,}" =~ ^(y|yes)$ ]]; then
        PACKAGES_TO_UNINSTALL+=("${DOCUMENT_SERVER_PACKAGES[@]}")
    else
        KEEP_DOCS=true
    fi
fi

DEPENDENCIES=(
    aspnetcore-runtime-10.0 opensearch opensearch-dashboards fluent-bit openresty
)

if [ "$UNINSTALL_DEPENDENCIES" = true ]; then
    # Docs may use either PostgreSQL or MySQL, including a pre-existing database.
    if [ "${KEEP_DOCS}" = false ]; then
        DEPENDENCIES+=(nodejs mysql-server mysql-client postgresql redis-server rabbitmq-server ffmpeg)
        mapfile -t -O "${#PACKAGES_TO_UNINSTALL[@]}" PACKAGES_TO_UNINSTALL < <(dpkg-query -W -f='${Package}\n' | grep -E "^postgresql(-[0-9]+)?(-.*)?$")
    fi
    PACKAGES_TO_UNINSTALL+=( "${DEPENDENCIES[@]}" )
fi

# Restore the standalone Docs configuration before removing Apps.
if [ "${KEEP_DOCS}" = true ]; then
    if [ "${LOCAL_SCRIPTS}" = "true" ]; then
        source common/restore-docs.sh
    else
        source_remote_script common/restore-docs.sh
    fi

    DS_CONF_FILE="/etc/${package_sysname}/documentserver/nginx/ds.conf"
    restore_docs_configuration "${DS_CONF_FILE}" || exit 1

    # Save only plain HTTP, preferring IPv4; Docs debconf accepts IPv4:port only.
    DS_LISTEN_ADDRESS="$(awk '
        { sub(/#.*/, ""); sub(/;.*/, "", $2) }
        $1 == "listen" && $0 !~ /[[:space:]](ssl|quic)([[:space:];]|$)/ {
            priority = 1
            if ($2 !~ /^([0-9.]+:)?[0-9]+$/) { sub(/.*:/, "", $2); priority++ }
            if ($2 ~ /^([0-9.]+:)?[0-9]+$/ && !(priority in addresses)) addresses[priority] = $2
        }
        END {
            for (priority = 1; priority <= 2; priority++)
                if (priority in addresses) { print (index(addresses[priority], ":") ? "" : "0.0.0.0:") addresses[priority]; exit }
        }
    ' "${DS_CONF_FILE}")"
    { [ -n "${DS_LISTEN_ADDRESS}" ] && command -v debconf-set-selections >/dev/null 2>&1 \
        && echo "${DOCUMENT_SERVER_PACKAGES[0]}" "${DS_COMMON_NAME:-onlyoffice}"/listenaddress string "${DS_LISTEN_ADDRESS}" | debconf-set-selections; } \
        || echo "Warning: could not determine or save the restored Docs HTTP listen address for future package updates." >&2
fi

# Stop app services before their dependencies disappear.
systemctl stop "${product}-*.service" "${legacy_product}-*.service" >/dev/null 2>&1 || true

# Uninstall packages and clean up
apt-get purge -y -o DPkg::Lock::Timeout=60 "${PACKAGES_TO_UNINSTALL[@]}"
[ "${KEEP_DOCS}" = true ] || apt-get autoremove -y -o DPkg::Lock::Timeout=60
apt-get clean

rm -f -- "/etc/cron.weekly/${product}-renew-letsencrypt" "/etc/cron.weekly/${legacy_product}-renew-letsencrypt" \
    /etc/letsencrypt/renewal-hooks/deploy/onlyoffice-apps-openresty
rm -f -- "/etc/${package_sysname}/documentserver/nginx/ds.conf".{apps.bak,ssl.bak} \
    "/etc/${package_sysname}/documentserver/nginx/ds.conf".apps.*.bak

# Uninstall swap file if it exists
for SWAPFILE_NAME in "${product}" "${legacy_product}"; do
    if swapon --show | grep -q "/${SWAPFILE_NAME}_swapfile"; then
        swapoff "/${SWAPFILE_NAME}_swapfile"
        rm -f "/${SWAPFILE_NAME}_swapfile"
    fi
done

echo -e "Uninstallation of ${product_name}" \
         "$( [ "$UNINSTALL_DEPENDENCIES" = true ] && { [ "${KEEP_DOCS}" = true ] && echo "and selected dependencies" || echo "and all dependencies"; } ) \e[32mcompleted.\e[0m"
