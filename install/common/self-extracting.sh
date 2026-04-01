#!/bin/bash
set -e

DOCSPACE_VERSION=""

PAYLOAD_LINE=$(awk '/^__END_OF_SHELL_SCRIPT__$/ {print NR+1; exit}' "$0")
TEMP_DIR=$(mktemp -d)
trap 'echo "Cleaning up temporary files..."; rm -rf "${TEMP_DIR}"' EXIT

for arg in "$@"; do
  case "$arg" in
    -h|-\?|--help)
      echo "Usage: $(basename "$0") [OPTIONS]"
      echo "Offline DocSpace installer. Docker images are bundled in this archive."
      echo "All options are passed to install-Docker.sh. Available options:"
      echo
      tail -n +"${PAYLOAD_LINE}" "$0" | tar -x -C "$TEMP_DIR" install-Docker-args.sh
      bash "$TEMP_DIR/install-Docker-args.sh" --help
      exit 0
    ;;
    --version)
      echo "DocSpace Stack v${DOCSPACE_VERSION:-unknown}"
      exit 0
    ;;
  esac
done

[ "$(id -u)" -ne 0 ] && { echo "To perform this action you must be logged in with root rights"; exit 1; }

SCRIPT_DIR=$(dirname "$0")

tail -n +"${PAYLOAD_LINE}" "$0" | tar -x -C "$TEMP_DIR" install-Docker-args.sh
source "$TEMP_DIR/install-Docker-args.sh" "$@"

! type docker &>/dev/null && { echo "docker not installed"; exit 1; }
docker compose version &>/dev/null || docker-compose version &>/dev/null || { echo "Docker Compose not installed"; exit 1; }

ARCHIVE_SIZE=$(( $(stat -c%s "$0") / 1024 / 1024 ))
AVAIL_MB=$(df -m "${TEMP_DIR}" | awk 'NR==2 {print $4}')
if [ "${AVAIL_MB}" -lt $(( ARCHIVE_SIZE * 3 )) ]; then
  echo "Warning: Low disk space. Archive is ~${ARCHIVE_SIZE}MB, available: ${AVAIL_MB}MB (recommended: $(( ARCHIVE_SIZE * 3 ))MB)"
fi

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
