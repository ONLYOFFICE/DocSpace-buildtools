#!/bin/bash

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

