#!/bin/bash
set -e

PAYLOAD_LINE=$(awk '/^__END_OF_SHELL_SCRIPT__$/ {print NR+1; exit}' "$0")
TEMP_DIR=$(mktemp -d)
trap 'echo "Cleaning up temporary files..."; rm -rf "${TEMP_DIR}"' EXIT

[ "$(id -u)" -ne 0 ] && { echo "To perform this action you must be logged in with root rights"; exit 1; }

SCRIPT_DIR=$(dirname "$0")

tail -n +"${PAYLOAD_LINE}" "$0" | tar -x -C "$TEMP_DIR" install-Docker-args.sh
source "$TEMP_DIR/install-Docker-args.sh" "$@"

! type docker &>/dev/null && { echo "docker not installed"; exit 1; }
docker compose version &>/dev/null || docker-compose version &>/dev/null || { echo "Docker Compose not installed"; exit 1; }

echo "Extracting docker images to ${TEMP_DIR}..."
tail -n +"${PAYLOAD_LINE}" "$0" | tar x -C "${TEMP_DIR}"

if [ "$OFFLINE_IMAGE_LOAD" != "true" ]; then
  echo "Loading docker images (this may take a few minutes)..."
  dd if="${TEMP_DIR}/docker_images.tar.xz" bs=1M status=progress | docker load
  dd if="${TEMP_DIR}/docs_images.tar.xz"   bs=1M status=progress | docker load
fi

echo "Extracting OneClickInstall files to the current directory..."
mv -f "${TEMP_DIR}/docker-stack.tar.gz" "${TEMP_DIR}/install-Docker.sh" "${TEMP_DIR}/install-Docker-args.sh" "${SCRIPT_DIR}"

echo "Running the install-Docker.sh script..."
chmod +x "${SCRIPT_DIR}/install-Docker.sh"
"${SCRIPT_DIR}/install-Docker.sh" "${UPDATE}" "$@"

exit 0

__END_OF_SHELL_SCRIPT__
