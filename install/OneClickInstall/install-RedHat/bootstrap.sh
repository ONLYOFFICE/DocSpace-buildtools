#!/bin/bash

set -e

cat<<EOF

#######################################
#  BOOTSTRAP
#######################################

EOF

if ! command -v ss >/dev/null 2>&1; then
	${package_manager} -y install iproute
fi
