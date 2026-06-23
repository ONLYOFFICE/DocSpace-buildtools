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
#  UNINSTALL ${package_sysname^^} ${product_name}
#######################################
"

# Ask to uninstall dependencies
read -r -p "Uninstall all dependencies (mysql, opensearch and others)? (Y/n): " DEP_CHOICE
DEP_CHOICE=${DEP_CHOICE,,}

if [[ "$DEP_CHOICE" =~ ^(y|yes|)$ ]]; then
    UNINSTALL_DEPENDENCIES=true
fi

# Get packages to uninstall
mapfile -t PACKAGES_TO_UNINSTALL < <(rpm -qa | grep -E "^(${package_sysname}|${product})" || true)

DEPENDENCIES=(
    nodejs dotnet-sdk-10.0 mysql-community-server postgresql
    postgresql-server redis rabbitmq-server ffmpeg opensearch
    opensearch-dashboards fluent-bit openresty
)

if [ "$UNINSTALL_DEPENDENCIES" = true ]; then
    rpm -q valkey &>/dev/null && DEPENDENCIES+=("valkey")
    PACKAGES_TO_UNINSTALL+=("${DEPENDENCIES[@]}")
fi

# Uninstall packages and clean up
yum remove -y "${PACKAGES_TO_UNINSTALL[@]}" --setopt=clean_requirements_on_remove=false --disableplugin=updateinfo
yum autoremove -y && yum clean all

# Uninstall swap file if it exists
if swapon --show | grep -q "/${product}_swapfile"; then
    swapoff "/${product}_swapfile"
    rm -f "/${product}_swapfile"
fi

echo -e "Uninstallation of ${package_sysname^^} ${product_name}" \
         "$( [ "$UNINSTALL_DEPENDENCIES" = true ] && echo "and all dependencies" ) \e[32mcompleted.\e[0m"

