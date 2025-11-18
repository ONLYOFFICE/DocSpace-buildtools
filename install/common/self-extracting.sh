#!/bin/bash
set -e

[ "$(id -u)" -ne 0 ] && { echo "To perform this action you must be logged in with root rights"; exit 1; }

TEMP_DIR=$(mktemp -d)

trap 'echo "Cleaning up temporary files..."; rm -rf "${TEMP_DIR}"' EXIT

tail -n +$(awk '/^__END_OF_SHELL_SCRIPT__$/ {print NR+1; exit}' "$0") "$0" | tar -x -C "$TEMP_DIR" install-Docker-args.sh
source "$TEMP_DIR/install-Docker-args.sh" "$@"

! type docker &> /dev/null && { echo "docker not installed"; exit 1; }
! type docker-compose &> /dev/null && { echo "docker-compose not installed"; exit 1; }

echo "Extracting docker images to ${TEMP_DIR}..."
tail -n +$(awk '/^__END_OF_SHELL_SCRIPT__$/{print NR + 1; exit 0;}' "$0") "$0" | tar x -C "${TEMP_DIR}"

[ "$OFFLINE_IMAGE_LOAD" != "true" ] && echo "Loading docker images..." && docker load -i "${TEMP_DIR}/docker_images.tar.xz" && docker load -i "${TEMP_DIR}/docs_images.tar.xz"

echo "Extracting OneClickInstall files to the current directory..."
mv -f ${TEMP_DIR}/{docker.tar.gz,install-Docker.sh,install-Docker-args.sh} $(dirname "$0")

echo "Running the install-Docker.sh script..."
chmod +x $(dirname "$0")/install-Docker.sh
$(dirname "$0")/install-Docker.sh ${UPDATE} "$@"

exit 0

__END_OF_SHELL_SCRIPT__
