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

_MISSING=0
_error_missing() {
  type "$1" &>/dev/null && return
  local pkg; type apt-get &>/dev/null && pkg="$2" || pkg="$3"
  echo "Error: '$1' not found. Install: ${pkg}"
  _MISSING=1
}

if ! type docker &>/dev/null; then
  _error_missing iptables iptables iptables; [ "$_MISSING" -eq 1 ] && exit 1

  echo "Installing Docker from bundled static binaries..."
  tail -n +"${PAYLOAD_LINE}" "$0" | tar -x -C "$TEMP_DIR" docker-static

  echo "  Installing Docker binaries..."
  tar -xzf "${TEMP_DIR}/docker-static/docker.tgz" -C /usr/local/bin --strip-components=1

  echo "  Installing Docker Compose plugin..."
  mkdir -p /usr/local/lib/docker/cli-plugins
  install -m 755 "${TEMP_DIR}/docker-static/docker-compose" /usr/local/lib/docker/cli-plugins/docker-compose

  echo "  Installing CNI plugins..."
  mkdir -p /opt/cni/bin
  tar -xzf "${TEMP_DIR}/docker-static/cni-plugins.tgz" -C /opt/cni/bin

  export PATH=/usr/local/bin:$PATH
  echo 'export PATH=/usr/local/bin:$PATH' > /etc/profile.d/docker-static.sh

  echo "  Configuring systemd services..."
  getent group docker &>/dev/null || groupadd docker
  SYSTEMD_DIR=$([ -d /usr/lib/systemd/system ] && echo /usr/lib/systemd/system || echo /lib/systemd/system)
  mkdir -p "${SYSTEMD_DIR}"
  find "${TEMP_DIR}/docker-static/systemd/" -maxdepth 1 -type f -exec cp {} "${SYSTEMD_DIR}/" \;
  systemctl daemon-reload
  systemctl enable --now containerd docker docker.socket 2>/dev/null || true

  if ! type docker &>/dev/null || ! systemctl is-active --quiet docker; then
    echo ""
    echo "ERROR: Failed to start Docker (installed from bundled static binaries)."
    echo "       Check logs: journalctl -xeu docker.service"
    echo ""
    echo "Cleaning up bundled installation..."
    systemctl disable --now containerd docker 2>/dev/null || true
    rm -f /usr/local/bin/{docker*,containerd*,ctr,runc} \
          /usr/local/lib/docker/cli-plugins/docker-compose \
          "${SYSTEMD_DIR}"/{docker.service,docker.socket,containerd.service} \
          /etc/profile.d/docker-static.sh && \
    rm -rf /opt/cni/bin
    systemctl daemon-reload
    echo ""
    echo "Please install Docker manually and re-run this script."
    echo "  https://docs.docker.com/engine/install/"
    exit 1
  fi
fi
docker compose version &>/dev/null || docker-compose version &>/dev/null || { echo "Docker Compose not installed"; exit 1; }

for pkg in tar iptables jq 'netstat:net-tools:net-tools' 'crontab:cron:cronie'; do
  IFS=: read -r cmd apt dnf <<< "$pkg"; _error_missing "$cmd" "${apt:-$cmd}" "${dnf:-$cmd}"
done
[ "$_MISSING" -eq 1 ] && exit 1

ARCHIVE_SIZE=$(( $(stat -c%s "$0") / 1024 / 1024 ))
AVAIL_MB=$(df -m "${TEMP_DIR}" | awk 'NR==2 {print $4}')
if [ "${AVAIL_MB}" -lt $(( ARCHIVE_SIZE * 3 )) ]; then
  echo "Warning: Low disk space. Archive is ~${ARCHIVE_SIZE}MB, available: ${AVAIL_MB}MB (recommended: $(( ARCHIVE_SIZE * 3 ))MB)"
fi

echo "Extracting docker images to ${TEMP_DIR}..."
tail -n +"${PAYLOAD_LINE}" "$0" | tar x -C "${TEMP_DIR}" --exclude='docker-static'

_load_image() {
  local file="$1" mb=$(( $(stat -c%s "$1") / 1024 / 1024 )) s='|/-\' i=0 t=0
  docker load -i "$file" &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  Loading %s (~%dMB) %s %ds" "$(basename "$file")" "$mb" "${s:i++%4:1}" "$t"
    sleep 1; (( t++ )) || true
  done
  wait "$pid"
  printf "\r  Loaded  %s (~%dMB) in %ds\n" "$(basename "$file")" "$mb" "$t"
}

if [ "$OFFLINE_IMAGE_LOAD" != "true" ]; then
  echo "Loading docker images (this may take a few minutes)..."
  _load_image "${TEMP_DIR}/docspace_images.tar.xz"
  _load_image "${TEMP_DIR}/docs_images.tar.xz"
fi

echo "Extracting OneClickInstall files to the current directory..."
mv -f "${TEMP_DIR}/docker-stack.tar.gz" "${TEMP_DIR}/install-Docker.sh" "${TEMP_DIR}/install-Docker-args.sh" "${SCRIPT_DIR}"

echo "Running the install-Docker.sh script..."
chmod +x "${SCRIPT_DIR}/install-Docker.sh"
if ! "${SCRIPT_DIR}/install-Docker.sh" "${UPDATE}" "$@"; then
  echo ""
  echo "ERROR: Installation failed. Fix the issue and re-run this script."
  echo "To clean up before retrying:"
  echo "  docker stop \$(docker ps -a -q); docker container prune -f; rm -rf /app/"
  echo "Then re-run: ${SCRIPT_DIR}/install-Docker.sh ${UPDATE} $@"
  exit 1
fi

exit 0

__END_OF_SHELL_SCRIPT__
