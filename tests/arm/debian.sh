#!/bin/bash
# Debian ARM64 test environment for the OCI Packages workflow.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ROOTFS="${RUNNER_TEMP:?}/apps-debian-rootfs"
INSTALL_DIR=/home/vagrant
cd "$REPO_DIR"

boot_debian() {
    local suite mirror
    case "${DEBIAN_VERSION:-}" in
        11) suite=bullseye; mirror=https://archive.debian.org/debian ;;
        12) suite=bookworm; mirror=https://deb.debian.org/debian ;;
        13) suite=trixie; mirror=https://deb.debian.org/debian ;;
        *) echo "Unsupported Debian release: ${DEBIAN_VERSION:-}" >&2; return 1 ;;
    esac
    sudo CLEAN_DOCKER=0 CLEAN_SWAP=0 bash .github/scripts/free-disk-space-linux.sh || true
    sudo systemctl stop mysql postgresql nginx apache2 redis-server rabbitmq-server 2>/dev/null || true
    sudo apt-get update
    sudo apt-get install -y debootstrap systemd-container gnupg
    sudo sysctl -w vm.max_map_count=1048576
    curl -fsSL "https://ftp-master.debian.org/keys/archive-key-${DEBIAN_VERSION}.asc" \
        | gpg --dearmor --batch --yes -o "$RUNNER_TEMP/debian-archive.gpg"
    sudo debootstrap --arch=arm64 --variant=minbase --components=main,contrib \
        --keyring="$RUNNER_TEMP/debian-archive.gpg" \
        --include=systemd-sysv,dbus,ca-certificates,curl,gnupg,iproute2,procps,lsb-release,locales,sudo,debconf-utils \
        "$suite" "$ROOTFS" "$mirror"
    printf 'deb [check-valid-until=no] %s %s main contrib\n' "$mirror" "$suite" \
        | sudo tee "$ROOTFS/etc/apt/sources.list"
    echo '127.0.1.1 apps-debian' | sudo tee -a "$ROOTFS/etc/hosts"
    sudo systemctl --root="$ROOTFS" mask apt-daily.timer apt-daily-upgrade.timer
    # Share the network and checkout path with the existing test scripts.
    sudo systemd-run --unit=apps-debian --service-type=exec \
        --property=Delegate=yes --property=KillMode=mixed --property=TasksMax=infinity \
        /usr/bin/systemd-nspawn --boot --keep-unit --machine=apps-debian \
        --directory="$ROOTFS" --console=read-only --resolv-conf=copy-host \
        --bind-ro="$REPO_DIR"
    for _ in $(seq 1 60); do
        if timeout 5s sudo systemctl --machine=apps-debian is-active --quiet dbus.service; then
            return 0
        fi
        sleep 2
    done
    echo "Debian systemd did not become ready" >&2
    return 1
}

run_in_debian() {
    sudo systemd-run --machine=apps-debian --wait --pipe --collect \
        /bin/bash -c 'cd "$1" && shift && exec "$@"' _ "$INSTALL_DIR" "$@"
}

case "${1:-}" in
    boot) boot_debian ;;
    install)
        ARGS=(-ds false -tr false -arg "--skiphardwarecheck true --localscripts true --makeswap false")
        if [[ "${USE_4TESTING:-false}" == true ]]; then
            ARGS=(-ds false -tr true -v "${VER:?}" -arg "--skiphardwarecheck true --localscripts true --makeswap false")
        fi
        sudo mkdir -p "$ROOTFS$INSTALL_DIR"
        # nspawn mounts its own /tmp; stage the installer inside the running guest.
        run_in_debian mkdir -p /tmp/apps
        run_in_debian cp -a "$REPO_DIR/install/OneClickInstall/." /tmp/apps/
        run_in_debian cp "$REPO_DIR/install/common/systemd/build.sh" /tmp/apps/build.sh
        run_in_debian /bin/bash "$REPO_DIR/tests/vagrant/install.sh" "${ARGS[@]}"
        ;;
    healthcheck|external-ports|uninstall)
        run_in_debian /bin/bash "$REPO_DIR/tests/vagrant/post-install.sh" "$1"
        ;;
    logs)
        run_in_debian /bin/bash "$REPO_DIR/tests/vagrant/post-install.sh" logs || true
        sudo journalctl -u apps-debian --no-pager || true
        ;;
    cleanup) sudo systemctl stop apps-debian.service || true ;;
    *)
        echo "Usage: $0 {boot|install|healthcheck|external-ports|uninstall|logs|cleanup}" >&2
        exit 1
        ;;
esac
