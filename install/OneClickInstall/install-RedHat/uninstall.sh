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
mapfile -t PACKAGES_TO_UNINSTALL < <(rpm -qa --qf '%{NAME}\n' | grep -E "^(${package}|${legacy_product})(-|$)" || true)

KEEP_DOCS=false
mapfile -t DOCUMENT_SERVER_PACKAGES < <(rpm -qa --qf '%{NAME}\n' | grep -E "^${package_sysname}-documentserver(-de|-ee)?$" || true)
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
        DEPENDENCIES+=(nodejs mysql-community-server postgresql postgresql-server redis rabbitmq-server ffmpeg)
        rpm -q valkey &>/dev/null && DEPENDENCIES+=("valkey")
    fi
    PACKAGES_TO_UNINSTALL+=("${DEPENDENCIES[@]}")
fi

# Restore the standalone Docs configuration before removing Apps.
if [ "${KEEP_DOCS}" = true ]; then
    if [ "${LOCAL_SCRIPTS}" = "true" ]; then
        source common/restore-docs.sh
    else
        source_remote_script common/restore-docs.sh
    fi

    restore_docs_configuration "/etc/${package_sysname}/documentserver/nginx/ds.conf" || exit 1
fi

# Stop app services before their dependencies disappear.
systemctl stop "${product}-*.service" "${legacy_product}-*.service" >/dev/null 2>&1 || true

# Uninstall packages and clean up
yum remove -y "${PACKAGES_TO_UNINSTALL[@]}" --setopt=clean_requirements_on_remove=false --disableplugin=updateinfo
[ "${KEEP_DOCS}" = true ] || yum autoremove -y
yum clean all

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
