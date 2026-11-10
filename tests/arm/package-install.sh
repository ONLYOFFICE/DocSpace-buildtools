#!/bin/bash
# ARM64 package installation checks for Debian and CentOS in the OCI Packages workflow.
set -euo pipefail

case "${GUEST_DISTRO:-}:${GUEST_VERSION:-}" in
    debian:11|debian:12|debian:13|centos:9|centos:10) ;;
    *) echo "Unsupported guest: ${GUEST_DISTRO:-} ${GUEST_VERSION:-}" >&2; exit 1 ;;
esac

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
MACHINE="apps-${GUEST_DISTRO}"
ROOTFS="${RUNNER_TEMP:?}/${MACHINE}-rootfs"
INSTALL_DIR=/home/vagrant
cd "$REPO_DIR"

prepare_debian() {
    local suite mirror
    case "$GUEST_VERSION" in
        11) suite=bullseye; mirror=https://archive.debian.org/debian ;;
        12) suite=bookworm; mirror=https://deb.debian.org/debian ;;
        13) suite=trixie; mirror=https://deb.debian.org/debian ;;
    esac
    sudo apt-get install -y debootstrap gnupg
    curl -fsSL "https://ftp-master.debian.org/keys/archive-key-${GUEST_VERSION}.asc" \
        | gpg --dearmor --batch --yes -o "$RUNNER_TEMP/debian-archive.gpg"
    sudo debootstrap --arch=arm64 --variant=minbase --components=main,contrib \
        --keyring="$RUNNER_TEMP/debian-archive.gpg" \
        --include=systemd-sysv,dbus,ca-certificates,curl,gnupg,iproute2,procps,lsb-release,locales,sudo,debconf-utils \
        "$suite" "$ROOTFS" "$mirror"
    printf 'deb [check-valid-until=no] %s %s main contrib\n' "$mirror" "$suite" \
        | sudo tee "$ROOTFS/etc/apt/sources.list"
    sudo systemctl --root="$ROOTFS" mask apt-daily.timer apt-daily-upgrade.timer
}

prepare_centos() {
    # Docker only prepares the rootfs; the test services run under nspawn's systemd.
    docker run --name "${MACHINE}-rootfs" --platform linux/arm64 \
        "quay.io/centos/centos:stream${GUEST_VERSION}" /bin/bash -ec '
            # Keep language files required by packages such as MySQL (english/errmsg.sys).
            rm -f /etc/rpm/macros.image-language-conf
            dnf -y install systemd dbus sudo ca-certificates curl-minimal gnupg2 iproute procps-ng util-linux hostname crypto-policies-scripts
            dnf clean all
        '
    sudo mkdir -p "$ROOTFS"
    docker export "${MACHINE}-rootfs" | sudo tar -xpf - -C "$ROOTFS"
    docker rm "${MACHINE}-rootfs"
}

boot_guest() {
    sudo CLEAN_DOCKER=0 CLEAN_SWAP=0 bash .github/scripts/free-disk-space-linux.sh || true
    sudo systemctl stop mysql postgresql nginx apache2 redis-server rabbitmq-server 2>/dev/null || true
    sudo apt-get update
    sudo apt-get install -y systemd-container
    sudo sysctl -w vm.max_map_count=1048576
    # The host MySQL profile also matches the guest binary, but only allows Ubuntu paths.
    if [[ "$GUEST_DISTRO" == centos ]] && \
        sudo grep -q '^/usr/sbin/mysqld ' /sys/kernel/security/apparmor/profiles 2>/dev/null; then
        echo "Unloading the runner MySQL AppArmor profile for the CentOS guest"
        sudo apparmor_parser -R /etc/apparmor.d/usr.sbin.mysqld
    fi
    case "$GUEST_DISTRO" in
        debian) prepare_debian ;;
        centos) prepare_centos ;;
    esac
    echo "127.0.1.1 $MACHINE" | sudo tee -a "$ROOTFS/etc/hosts"
    # Share the network and checkout path with the existing test scripts.
    sudo systemd-run --unit="$MACHINE" --service-type=exec \
        --property=Delegate=yes --property=KillMode=mixed --property=TasksMax=infinity \
        /usr/bin/systemd-nspawn --boot --keep-unit --machine="$MACHINE" \
        --directory="$ROOTFS" --console=read-only --resolv-conf=copy-host \
        --bind-ro="$REPO_DIR"
    for _ in $(seq 1 60); do
        if timeout 5s sudo systemctl --machine="$MACHINE" is-active --quiet dbus.service; then
            return 0
        fi
        sleep 2
    done
    echo "$GUEST_DISTRO $GUEST_VERSION systemd did not become ready" >&2
    return 1
}

run_in_guest() {
    sudo systemd-run --machine="$MACHINE" --wait --pipe --collect \
        /bin/bash -c 'cd "$1" && shift && exec "$@"' _ "$INSTALL_DIR" "$@"
}

case "${1:-}" in
    boot) boot_guest ;;
    install)
        ARGS=(-ds false -tr false -arg "--skiphardwarecheck true --localscripts true --makeswap false")
        if [[ "${USE_4TESTING:-false}" == true ]]; then
            ARGS=(-ds false -tr true -v "${VER:?}" -arg "--skiphardwarecheck true --localscripts true --makeswap false")
        fi
        sudo mkdir -p "$ROOTFS$INSTALL_DIR"
        # nspawn mounts its own /tmp; stage the installer inside the running guest.
        run_in_guest mkdir -p /tmp/apps
        run_in_guest cp -a "$REPO_DIR/install/OneClickInstall/." /tmp/apps/
        run_in_guest cp "$REPO_DIR/install/common/systemd/build.sh" /tmp/apps/build.sh
        run_in_guest /bin/bash "$REPO_DIR/tests/vagrant/install.sh" "${ARGS[@]}"
        ;;
    healthcheck|external-ports|uninstall)
        run_in_guest /bin/bash "$REPO_DIR/tests/vagrant/post-install.sh" "$1"
        ;;
    logs)
        run_in_guest /bin/bash "$REPO_DIR/tests/vagrant/post-install.sh" logs || true
        sudo journalctl -u "$MACHINE" --no-pager || true
        sudo journalctl -k -b --no-pager --grep='apparmor="DENIED"' || true
        ;;
    cleanup)
        sudo systemctl stop "${MACHINE}.service" || true
        if [[ "$GUEST_DISTRO" == centos ]]; then docker rm -f "${MACHINE}-rootfs" 2>/dev/null || true; fi
        ;;
    *)
        echo "Usage: $0 {boot|install|healthcheck|external-ports|uninstall|logs|cleanup}" >&2
        exit 1
        ;;
esac
