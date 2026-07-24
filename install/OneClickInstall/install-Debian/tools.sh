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

make_swap () {
	DISK_REQUIREMENTS=6144 #6Gb free space
	MEMORY_REQUIREMENTS=12000 #RAM ~12Gb
	SWAPFILE="/${product}_swapfile"

	AVAILABLE_DISK_SPACE=$(df -Pm / | awk 'NR == 2 { print $4 }')
	TOTAL_MEMORY=$(free --mega | awk '/^Mem:/ { print $2 }')
	EXIST=$(swapon -s | awk '{ print $1 }' | { grep -x "${SWAPFILE}" || true; })

	if [[ -z $EXIST ]] && [ "${TOTAL_MEMORY}" -lt ${MEMORY_REQUIREMENTS} ] && [ "${AVAILABLE_DISK_SPACE}" -gt ${DISK_REQUIREMENTS} ]; then
		touch "${SWAPFILE}"
		[[ "$(df -T / | awk 'NR==2{print $2}')" = "btrfs" ]] && chattr +C "${SWAPFILE}"
		fallocate -l 6G "${SWAPFILE}"
		chmod 600 "${SWAPFILE}"
		mkswap "${SWAPFILE}"
		swapon "${SWAPFILE}"
		echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
	fi
}

command_exists () {
	type "$1" &> /dev/null;
}

# Function to prevent package auto-update
hold_package_version() {
	packages=("dotnet-*" "aspnetcore-*" opensearch redis-server rabbitmq-server opensearch-dashboards fluent-bit)
	for package in "${packages[@]}"; do 
		command -v apt-mark >/dev/null 2>&1 && apt-mark showhold | grep -q "^$package" && apt-mark unhold "$package"
	done

	UNATTENDED_UPGRADES_FILE="/etc/apt/apt.conf.d/50unattended-upgrades"
	if [ -f ${UNATTENDED_UPGRADES_FILE} ] && grep -q "Package-Blacklist" ${UNATTENDED_UPGRADES_FILE}; then
		for package in "${packages[@]}"; do 
			if ! grep -q "$package" ${UNATTENDED_UPGRADES_FILE}; then
				sed -i "/Package-Blacklist/a \\\t\"$package\";" ${UNATTENDED_UPGRADES_FILE}
			fi
		done
		
		if systemctl list-units --type=service --state=running | grep -q "unattended-upgrades"; then
			systemctl restart unattended-upgrades
		fi
	fi
}

check_hardware () {
	local failed=0
	local DISK_REQUIREMENTS=40960
	local MEMORY_REQUIREMENTS=8000
	local CORE_REQUIREMENTS=4

	AVAILABLE_DISK_SPACE=$(df -Pm / | awk 'NR == 2 { print $4 }')
	TOTAL_MEMORY=$(free --mega | awk '/^Mem:/ { print $2 }')
	CPU_CORES_NUMBER=$(nproc)

	if (( AVAILABLE_DISK_SPACE < DISK_REQUIREMENTS )); then
		echo "Minimal requirements are not met: need at least ${DISK_REQUIREMENTS} MB of free disk space"
		echo "Available disk space: ${AVAILABLE_DISK_SPACE} MB"
		failed=1
	fi

	if (( TOTAL_MEMORY < MEMORY_REQUIREMENTS )); then
		echo "Minimal requirements are not met: need at least ${MEMORY_REQUIREMENTS} MB of RAM"
		echo "Available RAM: ${TOTAL_MEMORY} MB"
		failed=1
	fi

	if (( CPU_CORES_NUMBER < CORE_REQUIREMENTS )); then
		echo "Minimal requirements are not met: CPU with at least ${CORE_REQUIREMENTS} cores is required"
		echo "Available CPU cores: ${CPU_CORES_NUMBER}"
		failed=1
	fi

	if (( failed )); then
		exit 1
	fi
}

if [ "$SKIP_HARDWARE_CHECK" != "true" ]; then
	check_hardware
fi

ARCH="$(dpkg --print-architecture)"
if [ "$ARCH" != "amd64" ]; then
    echo "ONLYOFFICE ${product^^} doesn't support architecture '$ARCH'"
    exit
fi

REV=$(< /etc/debian_version)
DIST='Debian'
if [ -f /etc/lsb-release ] ; then
        DIST=$(grep '^DISTRIB_ID' /etc/lsb-release | awk -F= '{ print $2 }')
        REV=$(grep '^DISTRIB_RELEASE' /etc/lsb-release | awk -F= '{ print $2 }')
        DISTRIB_CODENAME=$(grep '^DISTRIB_CODENAME' /etc/lsb-release | awk -F= '{ print $2 }')
        DISTRIB_RELEASE=$(grep '^DISTRIB_RELEASE' /etc/lsb-release | awk -F= '{ print $2 }')
elif [ -f /etc/lsb_release ] || [ -f /usr/bin/lsb_release ] ; then
        DIST=$(lsb_release -a 2>&1 | grep 'Distributor ID:' | awk -F ":" '{print $2 }' | tr -d '[:space:]')
        REV=$(lsb_release -a 2>&1 | grep 'Release:' | awk -F ":" '{print $2 }' | tr -d '[:space:]')
        DISTRIB_CODENAME=$(lsb_release -a 2>&1 | grep 'Codename:' | awk -F ":" '{print $2 }' | tr -d '[:space:]')
        DISTRIB_RELEASE=$(lsb_release -a 2>&1 | grep 'Release:' | awk -F ":" '{print $2 }' | tr -d '[:space:]')
elif [ -f /etc/os-release ] ; then
        DISTRIB_CODENAME=$(grep '^VERSION=' /etc/os-release | awk -F= '{ print $2 }' | sed 's/"//g; s/[0-9]//g; s/)$//g; s/(//g' | tr -d '[:space:]')
        DISTRIB_RELEASE=$(grep '^VERSION_ID=' /etc/os-release | awk -F= '{ print $2 }' | sed 's/"//g; s/[0-9]//g; s/)$//g; s/(//g' | tr -d '[:space:]')
fi

DIST=$(echo "$DIST" | tr '[:upper:]' '[:lower:]' | xargs)
DISTRIB_CODENAME=$(echo "$DISTRIB_CODENAME" | tr '[:upper:]' '[:lower:]' | xargs)
[ "$DIST" = "debian" ] && REV="${REV%%.*}"

if [[ ( "${DIST}" == "ubuntu" && "${REV%.*}" -lt 22 ) || ( "${DIST}" == "debian" && "${REV}" -lt 11 ) ]]; then
    echo "Your ${DIST} ${REV} operating system has reached the end of its service life."
    echo "Please consider upgrading your operating system or using a Docker installation."
    exit 1
elif [[ "${DIST}" == "ubuntu" && ( $(( ${REV%.*} % 2 )) -ne 0 || "${REV#*.}" -ne 04 ) ]]; then
    echo "Only LTS versions of Ubuntu are supported." 
    echo "You are using ${DIST} ${REV}, which is not an LTS version."
    echo "Please consider upgrading to a LTS version or using a Docker installation."
    exit 1
fi
