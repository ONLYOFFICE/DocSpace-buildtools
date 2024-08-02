#!/bin/bash

set -e

function make_swap () {
	local DISK_REQUIREMENTS=6144; #6Gb free space
	local MEMORY_REQUIREMENTS=12000; #RAM ~12Gb
	SWAPFILE="/${product}_swapfile";

	local AVAILABLE_DISK_SPACE=$(df -m /  | tail -1 | awk '{ print $4 }');
	local TOTAL_MEMORY=$(free --mega | grep -oP '\d+' | head -n 1);
	local EXIST=$(swapon -s | awk '{ print $1 }' | { grep -x ${SWAPFILE} || true; });

	if [[ -z $EXIST ]] && [ ${TOTAL_MEMORY} -lt ${MEMORY_REQUIREMENTS} ] && [ ${AVAILABLE_DISK_SPACE} -gt ${DISK_REQUIREMENTS} ]; then
		touch "$SWAPFILE"
		# No Copy-on-Write - no compression
		[[ "$DIST" == "fedora" ]] && chattr +C "$SWAPFILE"
		# Allocate 6 GB, much faster than: dd if=/dev/zero of=${SWAPFILE} count=6144 bs=1MiB
		fallocate -l 6G "$SWAPFILE"
		chmod 600 "$SWAPFILE"
		mkswap "$SWAPFILE"
		# Activate, enable upon system boot
		swapon "$SWAPFILE"
		echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
	fi
}

check_hardware () {
    DISK_REQUIREMENTS=40960;
    MEMORY_REQUIREMENTS=8000;
    CORE_REQUIREMENTS=4;

	AVAILABLE_DISK_SPACE=$(df -m /  | tail -1 | awk '{ print $4 }');

	if [ ${AVAILABLE_DISK_SPACE} -lt ${DISK_REQUIREMENTS} ]; then
		echo "Minimal requirements are not met: need at least $DISK_REQUIREMENTS MB of free HDD space"
		exit 1;
	fi

	TOTAL_MEMORY=$(free --mega | grep -oP '\d+' | head -n 1);

	if [ ${TOTAL_MEMORY} -lt ${MEMORY_REQUIREMENTS} ]; then
		echo "Minimal requirements are not met: need at least $MEMORY_REQUIREMENTS MB of RAM"
		exit 1;
	fi

	CPU_CORES_NUMBER=$(cat /proc/cpuinfo | grep processor | wc -l);

	if [ ${CPU_CORES_NUMBER} -lt ${CORE_REQUIREMENTS} ]; then
		echo "The system does not meet the minimal hardware requirements. CPU with at least $CORE_REQUIREMENTS cores is required"
		exit 1;
	fi
}

if [ "$SKIP_HARDWARE_CHECK" != "true" ]; then
	check_hardware
fi

read_unsupported_installation () {
	read -p "$RES_CHOICE_INSTALLATION " CHOICE_INSTALLATION
	case "$CHOICE_INSTALLATION" in
		y|Y ) yum -y install $DIST*-release
		;;

		n|N ) exit 0;
		;;

		* ) echo $RES_CHOICE;
			read_unsupported_installation
		;;
	esac
}

DIST=$(rpm -qa --queryformat '%{NAME}\n' | grep -E 'centos-release|redhat-release|fedora-release' | awk -F '-' '{print $1}' | head -n 1)
DIST=${DIST:-$(awk -F= '/^ID=/ {gsub(/"/, "", $2); print tolower($2)}' /etc/os-release)}; 
[[ "$DIST" =~ ^(centos|redhat|fedora)$ ]] || DIST="centos"
REV=$(sed -n 's/.*release\ \([0-9]*\).*/\1/p' /etc/redhat-release)
REV=${REV:-"7"}

REMI_DISTR_NAME="enterprise"
RPMFUSION_DISTR_NAME="el"
MYSQL_DISTR_NAME="el"
OPENRESTY_DISTR_NAME="centos"
SUPPORTED_FEDORA_FLAG="true"

if [ "$DIST" == "fedora" ]; then
	REMI_DISTR_NAME="fedora"
	OPENRESTY_DISTR_NAME="fedora"
	RPMFUSION_DISTR_NAME="fedora"
	MYSQL_DISTR_NAME="fc"
	OPENRESTY_REV=$([ "$REV" -ge 37 ] && echo 36 || echo "$REV")

	FEDORA_SUPP=$(curl https://docs.fedoraproject.org/en-US/releases/ | awk '/Supported Releases/,/EOL Releases/' | grep -oP 'F\d+' | tr -d 'F')
	[ ! "$(echo "$FEDORA_SUPP" | grep "$REV")" ] && SUPPORTED_FEDORA_FLAG="false"
fi

# Check if it's Centos less than 8 or Fedora release is out of service
if [ "${REV}" -lt 8 ] || [ "$SUPPORTED_FEDORA_FLAG" == "false" ]; then
    echo "Your ${DIST} ${REV} operating system has reached the end of its service life."
    echo "Please consider upgrading your operating system or using a Docker installation."
    exit 1
fi
