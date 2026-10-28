#!/bin/bash
# Run inside the Debian nspawn guest, except for the read-only validate action.
set -euo pipefail

ACTION=${1:-validate}
DOCS_VERSION=${2:-}
APPS_VERSION=${3:-}
DS_PACKAGE=onlyoffice-documentserver-de
WORK_DIR=/opt/apps-ci

if [ "$ACTION" != logs ]; then
    [[ "$DOCS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]] \
        || { echo "Use the exact Docs DEB version, for example 10.0.0-156." >&2; exit 1; }
    [[ "$APPS_VERSION" =~ ^[0-9]+(\.[0-9]+){2,3}(-[0-9]+)?$ ]] \
        || { echo "Use the exact Apps DEB version from 4testing." >&2; exit 1; }
fi
[ "$ACTION" != validate ] || exit 0

# Never install packages on the Ubuntu host by accident.
[ "$(systemd-detect-virt --container)" = systemd-nspawn ]
[ "$(dpkg --print-architecture)" = arm64 ]
. /etc/os-release
[ "$ID" = debian ]
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

check_version() {
    local package="$1" expected="$2" installed
    installed=$(dpkg-query -W -f='${Version}' "$package")
    [ "$installed" = "$expected" ] || {
        echo "Unexpected $package version: $installed (expected $expected)" >&2
        exit 1
    }
    printf '%s %s\n' "$package" "$installed"
}

case "$ACTION" in
    docs)
        mkdir -p "$WORK_DIR"
        cp -a /workspace/install/OneClickInstall/. "$WORK_DIR/"
        cp /workspace/install/common/systemd/build.sh "$WORK_DIR/build.sh"

        curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
            | gpg --batch --yes --dearmor -o /usr/share/keyrings/onlyoffice.gpg
        echo "deb [trusted=yes] https://s3.eu-west-1.amazonaws.com/repo-doc-onlyoffice-com/repo/debian stable ${DOCS_VERSION%%-*}" \
            > /etc/apt/sources.list.d/onlyoffice-dev.list
        apt-get update
        echo 'ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true' | debconf-set-selections
        apt-get install -y postgresql redis-server rabbitmq-server nginx-extras openssl
        systemctl start postgresql redis-server rabbitmq-server
        DOCS_DB_PASSWORD=$(openssl rand -hex 16)
        runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "CREATE ROLE ds WITH LOGIN PASSWORD '${DOCS_DB_PASSWORD}';"
        runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c 'CREATE DATABASE ds OWNER ds;'
        debconf-set-selections <<EOF
${DS_PACKAGE} onlyoffice/db-type string postgres
${DS_PACKAGE} onlyoffice/db-host string localhost
${DS_PACKAGE} onlyoffice/db-user string ds
${DS_PACKAGE} onlyoffice/db-pwd password ${DOCS_DB_PASSWORD}
${DS_PACKAGE} onlyoffice/db-name string ds
EOF
        apt-get install -y "${DS_PACKAGE}=${DOCS_VERSION}"
        check_version "$DS_PACKAGE" "$DOCS_VERSION" | tee "$WORK_DIR/docs-version.before"
        for _ in $(seq 1 60); do
            if [ "$(curl -fsS --max-time 5 http://localhost/healthcheck || true)" = true ]; then
                exit 0
            fi
            sleep 2
        done
        echo "Standalone Docs healthcheck failed before installing Apps" >&2
        exit 1
        ;;
    apps)
        cd "$WORK_DIR"
        check_version "$DS_PACKAGE" "$DOCS_VERSION"
        echo 'deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://nexus.onlyoffice.com/repository/4testing-debian stable main' \
            > /etc/apt/sources.list.d/onlyoffice4testing.list
        apt-get update
        apt-cache policy onlyoffice-apps onlyoffice-apps-common
        # No swap inside nspawn; the disposable runner supplies it. Use the checked-out scripts.
        bash apps-install.sh package -ls true -it developer -av "$APPS_VERSION" -skiphc true -ms false -log false
        ;;
    verify)
        cd "$WORK_DIR"
        check_version "$DS_PACKAGE" "$DOCS_VERSION" | tee docs-version.after
        cmp docs-version.before docs-version.after
        check_version onlyoffice-apps "$APPS_VERSION"
        check_version onlyoffice-apps-common "$APPS_VERSION"
        PERCONA_VERSION=$(dpkg-query -W -f='${Version}' percona-server-server)
        [[ "$PERCONA_VERSION" = 8.4.* ]] || { echo "Expected Percona 8.4, found $PERCONA_VERSION" >&2; exit 1; }
        systemctl is-active mysql
        AUDIT=$(dpkg --audit)
        [ -z "$AUDIT" ] || { printf '%s\n' "$AUDIT" >&2; exit 1; }
        bash /workspace/tests/vagrant/post-install.sh healthcheck
        ;;
    logs)
        set +e
        cd "$WORK_DIR" || exit 0
        dpkg-query -W -f='${Package}\t${Version}\t${db:Status-Status}\n' 'onlyoffice*' 'percona*'
        bash /workspace/tests/vagrant/post-install.sh logs
        journalctl -b --no-pager -n 1000
        ;;
    *)
        echo "Usage: $0 {validate|docs|apps|verify|logs} DOCS_DEB_VERSION APPS_DEB_VERSION" >&2
        exit 1
        ;;
esac
