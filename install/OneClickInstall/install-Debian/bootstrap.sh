#!/bin/bash

set -e

cat<<EOF

#######################################
#  BOOTSTRAP
#######################################

EOF

if [ -f /etc/needrestart/needrestart.conf ]; then
	sed -e "s_#\$nrconf{restart}_\$nrconf{restart}_" -e "s_\(\$nrconf{restart} =\).*_\1 'a';_" -i /etc/needrestart/needrestart.conf
fi

for PACKAGE in sudo net-tools dirmngr debian-archive-keyring debconf-utils locales apt-transport-https software-properties-common; do
	dpkg -l | grep -qw "$PACKAGE" || apt-get install -yq "$PACKAGE"
done

locale-gen en_US.UTF-8
