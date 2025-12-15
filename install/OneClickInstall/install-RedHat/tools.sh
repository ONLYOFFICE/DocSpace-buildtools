#!/bin/bash

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
DIST=$(rpm -qa --queryformat '%{NAME}\n' | grep -E 'centos-release|redhat-release|fedora-release' | awk -F '-' '{print $1}' | head -n 1)
DIST=${DIST:-$(awk -F= '/^ID=/ {gsub(/"/, "", $2); print tolower($2)}' /etc/os-release)}
[[ "$DIST" =~ ^(centos|redhat|fedora)$ ]] || DIST="centos"
REV=$( . /etc/os-release; echo "${VERSION_ID%%.*}" )
REV=${REV:-"7"}

REMI_DISTR_NAME="enterprise"
RPMFUSION_DISTR_NAME="el"
MYSQL_DISTR_NAME="el"
OPENRESTY_DISTR_NAME=${DIST/redhat/rhel}
SUPPORTED_FEDORA_FLAG="true"
REDIS_PACKAGE=$( [[ "$REV" == "10" ]] && echo "valkey" || echo "redis" )
RABBIT_DIST_NAME=$( [[ "$REV" == "10" ]] && echo "el" || echo "$DIST" )
RABBIT_DIST_VER=$( [[ "$REV" == "10" ]] && echo "9" || echo "$REV" )
ERLANG_DIST_NAME=$( [[ "$REV" == "10" ]] && echo "el" || echo "$DIST" )
ERLANG_DIST_VER=$( [[ "$REV" == "10" ]] && echo "9" || echo "$REV" )

if [ "$REV" = "10" ]; then
  OPENRESTY_REV="9"
  DNF_NOGPG="--nogpgcheck"
  # Temporary workaround for missing CentOS 10 repos
  APPSTREAM_PKGS="https://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/Packages"
  yum -y install  "$APPSTREAM_PKGS/$(curl -fsSL "$APPSTREAM_PKGS/" | grep -oE 'libXScrnSaver-[0-9][^"]+\.x86_64\.rpm' | sort -V | tail -1)" \
                  "$APPSTREAM_PKGS/$(curl -fsSL "$APPSTREAM_PKGS/" | grep -oE 'xorg-x11-server-common-[0-9][^"]+\.x86_64\.rpm' | sort -V | tail -1)" \
                  "$APPSTREAM_PKGS/$(curl -fsSL "$APPSTREAM_PKGS/" | grep -oE 'xorg-x11-server-Xvfb-[0-9][^"]+\.x86_64\.rpm' | sort -V | tail -1)"
  # Disable on CentOS 10 Cockpit to free 9090 needed by docspace-identity-api
  systemctl list-sockets | grep -q '9090.*cockpit\.socket' && sudo systemctl stop cockpit.{service,socket} && sudo systemctl disable cockpit.socket || true
fi

if [ "$DIST" == "fedora" ]; then
	REMI_DISTR_NAME="fedora"
	RPMFUSION_DISTR_NAME="fedora"
	MYSQL_DISTR_NAME="fc"
	OPENRESTY_REV=$([ "$REV" -ge 37 ] && echo 36 || echo "$REV")

	FEDORA_SUPP=$(curl https://docs.fedoraproject.org/en-US/releases/ | awk '/Supported Releases/,/EOL Releases/' | grep -oP 'F\d+' | tr -d 'F')
	echo "$FEDORA_SUPP" | grep -q "$REV" || SUPPORTED_FEDORA_FLAG="false"
fi

# Check if it's Centos less than 8 or Fedora release is out of service
if { [[ "${DIST}" == "centos" && "${REV}" -lt 9 ]] || \
     [[ "${DIST}" == "redhat" && "${REV}" -lt 8 ]] || \
     [[ "$SUPPORTED_FEDORA_FLAG" == "false" ]]; }; then
    echo "Your ${DIST} ${REV} operating system has reached the end of its service life."
    echo "Please consider upgrading your operating system or using a Docker installation."
    exit 1
fi
