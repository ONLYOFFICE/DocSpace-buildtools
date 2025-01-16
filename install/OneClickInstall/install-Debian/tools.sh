#!/bin/bash

set -e

make_swap () {
	DISK_REQUIREMENTS=6144 #6Gb free space
	MEMORY_REQUIREMENTS=12000 #RAM ~12Gb
	SWAPFILE="/${product}_swapfile"

	AVAILABLE_DISK_SPACE=$(df -m /  | tail -1 | awk '{ print $4 }')
	TOTAL_MEMORY=$(free --mega | grep -oP '\d+' | head -n 1)
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

	if [ ${CPU_CORES_NUMBER} -lt ${CORE_REQUIREMENTS} ]; then
		echo "The system does not meet the minimal hardware requirements. CPU with at least $CORE_REQUIREMENTS cores is required"
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

if [[ ( "${DIST}" == "ubuntu" && "${REV%.*}" -lt 22 ) || ( "${DIST}" == "debian" && "${REV%.*}" -lt 12 ) ]]; then
    echo "Your ${DIST} ${REV} operating system has reached the end of its service life."
    echo "Please consider upgrading your operating system or using a Docker installation."
    exit 1
elif [[ "${DIST}" == "ubuntu" && ( $(( ${REV%.*} % 2 )) -ne 0 || "${REV#*.}" -ne 04 ) ]]; then
    echo "Only LTS versions of Ubuntu are supported." 
    echo "You are using ${DIST} ${REV}, which is not an LTS version."
    echo "Please consider upgrading to a LTS version or using a Docker installation."
    exit 1
fi
