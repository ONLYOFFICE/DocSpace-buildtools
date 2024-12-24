#!/bin/bash
set -e

[ "$(id -u)" -ne 0 ] && { echo "To perform this action you must be logged in with root rights"; exit 1; }

TEMP_DIR=$(mktemp -d)

trap 'echo "Cleaning up temporary files..."; rm -rf "${TEMP_DIR}"' EXIT

! type docker &> /dev/null && { echo "docker not installed"; exit 1; }
! type docker-compose &> /dev/null && { echo "docker-compose not installed"; exit 1; }

echo "Extracting docker images to ${TEMP_DIR}..."
tail -n +$(awk '/^__END_OF_SHELL_SCRIPT__$/{print NR + 1; exit 0;}' "$0") "$0" | tar x -C "${TEMP_DIR}"

echo "Loading docker images..."
docker load -i ${TEMP_DIR}/docker_images.tar.xz

echo "Extracting OneClickInstall files to the current directory..."
mv -f ${TEMP_DIR}/docker.tar.gz $(dirname "$0")/docker.tar.gz
mv -f ${TEMP_DIR}/install-Docker.sh $(dirname "$0")/install-Docker.sh

#Check if an update is needed
docker ps -aqf name=$(grep -oP 'PACKAGE_SYSNAME="\K[^"]+' $(dirname "$0")/install-Docker.sh)-api && UPDATE="-u true" 

echo "Running the install-Docker.sh script..."
chmod +x $(dirname "$0")/install-Docker.sh
$(dirname "$0")/install-Docker.sh ${UPDATE}

exit 0

__END_OF_SHELL_SCRIPT__
