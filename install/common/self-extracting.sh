#!/bin/bash
set -e

[ "$(id -u)" -ne 0 ] && { echo "To perform this action you must be logged in with root rights"; exit 1; }

TEMP_DIR=$(mktemp -d)
echo "Unpacking files to ${TEMP_DIR}..."
tail -n +$(awk '/^__END_OF_SHELL_SCRIPT__$/{print NR + 1; exit 0;}' "$0") "$0" | tar xv -C "$TEMP_DIR"

echo "Loading Docker images from docker_images.tgz..."
docker load -i ${TEMP_DIR}/docker_images.tgz

echo "Run the ${TEMP_DIR}/install-Docker.sh script..."
chmod +x ${TEMP_DIR}/install-Docker.sh
${TEMP_DIR}/install-Docker.sh

rm -rf "${TEMP_DIR}"

exit 0

__END_OF_SHELL_SCRIPT__