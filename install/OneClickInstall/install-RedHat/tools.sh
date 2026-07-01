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

function make_swap () {
	local DISK_REQUIREMENTS=6144 #6Gb free space
	local MEMORY_REQUIREMENTS=12000 #RAM ~12Gb
	SWAPFILE="/${product}_swapfile"

	local AVAILABLE_DISK_SPACE=$(df -m /  | tail -1 | awk '{ print $4 }')
	local TOTAL_MEMORY=$(free --mega | grep -oP '\d+' | head -n 1)
	local EXIST=$(swapon -s | awk '{ print $1 }' | { grep -x ${SWAPFILE} || true; })

	if [[ -z $EXIST ]] && [ "${TOTAL_MEMORY}" -lt ${MEMORY_REQUIREMENTS} ] && [ "${AVAILABLE_DISK_SPACE}" -gt ${DISK_REQUIREMENTS} ]; then
		touch "$SWAPFILE"
		[[ "$(df -T / | awk 'NR==2{print $2}')" = "btrfs" ]] && chattr +C "$SWAPFILE"
		fallocate -l 6G "$SWAPFILE"
		chmod 600 "$SWAPFILE"
		mkswap "$SWAPFILE"
		swapon "$SWAPFILE"
		echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
	fi
}

check_hardware () {
    DISK_REQUIREMENTS=40960
    MEMORY_REQUIREMENTS=8000
    CORE_REQUIREMENTS=4

	AVAILABLE_DISK_SPACE=$(df -m /  | tail -1 | awk '{ print $4 }')

	if [ "${AVAILABLE_DISK_SPACE}" -lt ${DISK_REQUIREMENTS} ]; then
		echo "Minimal requirements are not met: need at least $DISK_REQUIREMENTS MB of free HDD space"
		exit 1
	fi

	TOTAL_MEMORY=$(free --mega | grep -oP '\d+' | head -n 1)

	if [ "${TOTAL_MEMORY}" -lt ${MEMORY_REQUIREMENTS} ]; then
		echo "Minimal requirements are not met: need at least $MEMORY_REQUIREMENTS MB of RAM"
		exit 1
	fi

	CPU_CORES_NUMBER=$(grep -c ^processor /proc/cpuinfo)

	if [ "${CPU_CORES_NUMBER}" -lt ${CORE_REQUIREMENTS} ]; then
		echo "The system does not meet the minimal hardware requirements. CPU with at least $CORE_REQUIREMENTS cores is required"
		exit 1
	fi
}

if [ "$SKIP_HARDWARE_CHECK" != "true" ]; then
	check_hardware
fi

UPDATE_AVAILABLE_CODE=100
ARCH="$(rpm --eval '%{_arch}')"
if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
    echo "${package_sysname^^} ${product^^} doesn't support architecture '$ARCH'"
    exit 1
fi

DIST=$(rpm -qa --queryformat '%{NAME}\n' | grep -E 'centos-release|redhat-release|fedora-release' | awk -F '-' '{print $1}' | head -n 1)
DIST=${DIST:-$(awk -F= '/^ID=/ {gsub(/"/, "", $2); print tolower($2)}' /etc/os-release)}
[[ "$DIST" =~ ^(centos|redhat|fedora)$ ]] || DIST="centos"
REV=$( . /etc/os-release; echo "${VERSION_ID%%.*}" )
REV=${REV:-"7"}

REMI_DISTR_NAME="enterprise"
RPMFUSION_DISTR_NAME="el"
MYSQL_DISTR_NAME="el"
MYSQL_REPO_REV="$REV"
OPENRESTY_DISTR_NAME=${DIST/redhat/rhel}
REDIS_PACKAGE=$( [[ "$REV" == "8" || "$REV" == "10" ]] && echo "valkey" || echo "redis" )
RABBIT_DIST_NAME=$( [[ "$REV" == "10" ]] && echo "el" || echo "$DIST" )
RABBIT_DIST_VER=$( [[ "$REV" == "10" ]] && echo "9" || echo "$REV" )
ERLANG_DIST_NAME=$( [[ "$REV" == "10" ]] && echo "el" || echo "$DIST" )
ERLANG_DIST_VER=$( [[ "$REV" == "10" ]] && echo "9" || echo "$REV" )

if [ "$REV" = "10" ]; then
  OPENRESTY_REV="9"
  DNF_NOGPG="--nogpgcheck"
fi

if [ "$DIST" == "fedora" ]; then
	REMI_DISTR_NAME="fedora"
	RPMFUSION_DISTR_NAME="fedora"
	MYSQL_DISTR_NAME="fc"
	MYSQL_REPO_REV=$([ "$REV" = "44" ] && echo 43 || echo "$REV")
	OPENRESTY_REV=$([ "$REV" -ge 37 ] && echo 36 || echo "$REV")
fi

# Disable Cockpit to free 9090 needed by docspace-identity-api
systemctl list-sockets | awk '$1 ~ /:9090$/ && $2 ~ /cockpit/ {print $2; exit}' | xargs -r systemctl disable --now 2>/dev/null || true

# Check if it's Centos less than 8 or Fedora release is out of service
if { [[ "${DIST}" == "centos" && "${REV}" -lt 9 ]] || \
     [[ "${DIST}" == "redhat" && "${REV}" -lt 8 ]] || \
     { [[ "${DIST}" == "fedora" ]] && ( . /etc/os-release; [ -n "${SUPPORT_END:-}" ] && [ "$(date -d "$SUPPORT_END" +%Y%m%d)" -lt "$(date +%Y%m%d)" ] ); }; }; then
    echo "Your ${DIST} ${REV} operating system has reached the end of its service life."
    echo "Please consider upgrading your operating system or using a Docker installation."
    exit 1
fi
