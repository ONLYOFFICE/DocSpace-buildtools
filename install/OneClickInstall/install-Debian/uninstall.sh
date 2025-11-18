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
mapfile -t PACKAGES_TO_UNINSTALL < <(dpkg -l | awk '{print $2}' | grep -E "^(${package_sysname}|${product})" || true)

DEPENDENCIES=(
    nodejs dotnet-sdk-10.0 mysql-server mysql-client postgresql
    redis-server rabbitmq-server ffmpeg opensearch
    opensearch-dashboards fluent-bit openresty
)

if [ "$UNINSTALL_DEPENDENCIES" = true ]; then
    PACKAGES_TO_UNINSTALL+=( "${DEPENDENCIES[@]}" )
    mapfile -t -O "${#PACKAGES_TO_UNINSTALL[@]}" PACKAGES_TO_UNINSTALL < <(dpkg-query -W -f='${Package}\n' | grep -E "^postgresql(-[0-9]+)?(-.*)?$")
fi

# Uninstall packages and clean up
apt-get purge -y "${PACKAGES_TO_UNINSTALL[@]}" && apt-get autoremove -y && apt-get clean

# Uninstall swap file if it exists
if swapon --show | grep -q "/${product}_swapfile"; then
    swapoff "/${product}_swapfile"
    rm -f "/${product}_swapfile"
fi

echo -e "Uninstallation of ${package_sysname^^} ${product_name}" \
         "$( [ "$UNINSTALL_DEPENDENCIES" = true ] && echo "and all dependencies" ) \e[32mcompleted.\e[0m"

