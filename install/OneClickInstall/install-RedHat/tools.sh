#!/bin/bash

set -e

make_swap () {
	local DISK_REQUIREMENTS=6144 MEMORY_REQUIREMENTS=12000 SWAPFILE="/${product}_swapfile"
	local AVAILABLE_DISK_SPACE=$(df -m / | awk 'END {print $4}')
	local TOTAL_MEMORY=$(free --mega | awk '/Mem:/ {print $2}')
	local EXIST=$(swapon -s | awk '{print $1}' | grep -x "$SWAPFILE" || true)

	if [[ -z $EXIST && $TOTAL_MEMORY -lt $MEMORY_REQUIREMENTS && $AVAILABLE_DISK_SPACE -gt $DISK_REQUIREMENTS ]]; then
		touch "$SWAPFILE"
		[[ "$DIST" == "fedora" ]] && chattr +C "$SWAPFILE"
		fallocate -l 6G "$SWAPFILE"
		chmod 600 "$SWAPFILE"
		mkswap "$SWAPFILE"
		swapon "$SWAPFILE"
		echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
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

read_unsupported_installation () {
	read -p "$RES_CHOICE_INSTALLATION " CHOICE_INSTALLATION
	case "$CHOICE_INSTALLATION" in
		y|Y) yum -y install "$DIST*-release";;
		n|N) exit 0;;
		*) echo "$RES_CHOICE"; read_unsupported_installation;;
	esac
}


DIST=$(rpm -qa --queryformat '%{NAME}\n' | grep -E 'centos-release|redhat-release|fedora-release' | awk -F '-' '{print $1}' | head -n 1)
DIST=${DIST:-$(awk -F= '/^ID=/ {gsub(/"/, "", $2); print tolower($2)}' /etc/os-release)}; 
[[ "$DIST" =~ ^(centos|redhat|fedora)$ ]] || DIST="centos"
REV=$(sed -n 's/.*release\ \([0-9]*\).*/\1/p' /etc/redhat-release)
REV=${REV:-"8"}

if [ "$DIST" == "fedora" ]; then
	REMI_DISTR_NAME="fedora"
	OPENRESTY_DISTR_NAME="fedora"
	RPMFUSION_DISTR_NAME="fedora"
	MYSQL_DISTR_NAME="fc"
	FEDORA_SUPPORTED=$(curl -s https://docs.fedoraproject.org/en-US/releases/ | awk '/Supported Releases/,/EOL Releases/' | grep -oP 'F\d+' | tr -d 'F')
else
	REMI_DISTR_NAME="enterprise"
	OPENRESTY_DISTR_NAME="centos"
	RPMFUSION_DISTR_NAME="el"
	MYSQL_DISTR_NAME="el"
fi

# Check if it's Centos less than 8 or Fedora release is out of service
if [ "${REV}" -lt 8 ] || [[ "$DIST" == "fedora" && ! "$FEDORA_SUPPORTED" =~ $REV ]]; then
    echo "Your ${DIST} ${REV} operating system has reached the end of its service life."
    echo "Please consider upgrading your operating system or using a Docker installation."
    exit 1
fi
