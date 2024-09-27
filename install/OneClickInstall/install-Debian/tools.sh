#!/bin/bash

set -e

make_swap () {
	local DISK_REQUIREMENTS=6144 MEMORY_REQUIREMENTS=12000 SWAPFILE="/${product}_swapfile"
	local AVAILABLE_DISK_SPACE=$(df -m / | awk 'END {print $4}')
	local TOTAL_MEMORY=$(free --mega | awk '/Mem:/ {print $2}')
	local EXIST=$(swapon -s | awk '{print $1}' | grep -x "$SWAPFILE" || true)

	if [[ -z $EXIST && $TOTAL_MEMORY -lt $MEMORY_REQUIREMENTS && $AVAILABLE_DISK_SPACE -gt $DISK_REQUIREMENTS ]]; then
		touch "${SWAPFILE}"
		[[ "$(df -T / | awk 'NR==2{print $2}')" = "btrfs" ]] && chattr +C "${SWAPFILE}"
		fallocate -l 6G "$SWAPFILE"
		chmod 600 "$SWAPFILE"
		mkswap "$SWAPFILE"
		swapon "$SWAPFILE"
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

if [ "$SKIP_HARDWARE_CHECK" != "true" ]; then
	DISK_REQUIREMENTS=40960
	MEMORY_REQUIREMENTS=8000
	CORE_REQUIREMENTS=4

	AVAILABLE_DISK_SPACE=$(df -m / | awk 'END {print $4}')
	[ $AVAILABLE_DISK_SPACE -lt $DISK_REQUIREMENTS ] && { echo "Need at least $DISK_REQUIREMENTS MB of free HDD space"; exit 1; }

	TOTAL_MEMORY=$(free --mega | awk '/Mem:/ {print $2}')
	[ $TOTAL_MEMORY -lt $MEMORY_REQUIREMENTS ] && { echo "Need at least $MEMORY_REQUIREMENTS MB of RAM"; exit 1; }

	CPU_CORES_NUMBER=$(grep -c processor /proc/cpuinfo)
	[ $CPU_CORES_NUMBER -lt $CORE_REQUIREMENTS ] && { echo "CPU with at least $CORE_REQUIREMENTS cores is required"; exit 1; }
fi

[ "$(dpkg --print-architecture)" != "amd64" ] && { echo "ONLYOFFICE ${product^^} doesn't support architecture '$(dpkg --print-architecture)'"; exit; }

if command -v lsb_release >/dev/null; then
    DIST=$(lsb_release -si | xargs)
    DISTRIB_CODENAME=$(lsb_release -sc | xargs)
    REV=$(lsb_release -sr | xargs)
elif [ -f /etc/os-release ]; then
    DIST=$(grep -Po '(?<=^ID=)"?\K[^"]+' /etc/os-release)
    DISTRIB_CODENAME=$(grep -Po '(?<=VERSION_CODENAME=)"?\K[^"]+' /etc/os-release)
    REV=$(grep -Po '(?<=VERSION_ID=)"?\K[^"]+' /etc/os-release)
fi

DIST=${DIST,,} 
DISTRIB_CODENAME=${DISTRIB_CODENAME,,}

# Check if it's Ubuntu less than 20 or Debian less than 11
if [[ ( "${DIST}" == "ubuntu" && "${REV%.*}" -lt 20 ) || ( "${DIST}" == "debian" && "${REV%.*}" -lt 11 ) ]]; then
    echo "Your ${DIST} ${REV} operating system has reached the end of its service life."
    echo "Please consider upgrading your operating system or using a Docker installation."
    exit 1
fi
