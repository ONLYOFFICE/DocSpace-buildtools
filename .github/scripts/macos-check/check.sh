#!/bin/bash
# Checks the macOS-specific paths of the Docker installer on a real macOS runner without a Docker VM: docker is a fake CLI.
# It covers the Homebrew bootstrap, bash 3.2 and BSD tools, OS and port detection, the Docker Desktop start, the volume helper and the rejected options.
# It does not start any container, so it says nothing about the product itself.

set -u

REPO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPTS_DIR="${REPO_DIR}/install/OneClickInstall"
FAKE_BIN="${REPO_DIR}/.github/scripts/macos-check/fake-bin"
WORK_DIR="$(mktemp -d)"
FAILURES=0
SCENARIO_NUMBER=0

chmod +x "${FAKE_BIN}/docker" "${FAKE_BIN}/open"

# Same layout as the offline archive of the release: the scripts and docker-standalone.tar.gz side by side
INSTALL_DIR="${WORK_DIR}/oci"
mkdir -p "${INSTALL_DIR}"
cp "${SCRIPTS_DIR}"/{apps-install,install-Docker,install-Docker-args,install-Docker-docs}.sh "${INSTALL_DIR}/"
mkdir -p "${INSTALL_DIR}/common" && cp "${SCRIPTS_DIR}/common/swap.sh" "${INSTALL_DIR}/common/"
( cd "${REPO_DIR}/install/docker/standalone" && tar -czf "${INSTALL_DIR}/docker-standalone.tar.gz" .env docker-compose.yml config )

# Every scenario gets its own HOME and fake Docker state, so nothing leaks between them
new_scenario () {
    SCENARIO_NUMBER=$((SCENARIO_NUMBER + 1))
    SCENARIO_NAME="$1"
    SCENARIO_HOME="${WORK_DIR}/home${SCENARIO_NUMBER}"
    FAKE_DOCKER_STATE="${WORK_DIR}/state${SCENARIO_NUMBER}"
    OUT_FILE="${WORK_DIR}/out${SCENARIO_NUMBER}.txt"
    mkdir -p "${SCENARIO_HOME}" "${FAKE_DOCKER_STATE}"
    printf 'onlyoffice/apps:4.0.1\nonlyoffice/documentserver:4.0.1\n' > "${FAKE_DOCKER_STATE}/images"
    : > "${FAKE_DOCKER_STATE}/docker.log"
    echo "::group::${SCENARIO_NUMBER}. ${SCENARIO_NAME}"
}

# Runs the installer wrapper the way a user does, without sudo, Docker Desktop stopped
run_wrapper () {
    ( cd "${INSTALL_DIR}" && HOME="${SCENARIO_HOME}" FAKE_DOCKER_STATE="${FAKE_DOCKER_STATE}" PATH="${FAKE_BIN}:${PATH}" \
        bash apps-install.sh "$@" < /dev/null ) > "${OUT_FILE}" 2>&1
    RC=$?
}

fail () {
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

expect_rc () {
    [ "${RC}" -eq "$1" ] || fail "exit code ${RC}, expected $1"
}

expect_output () {
    grep -qF -- "$1" "${OUT_FILE}" || fail "the output has no '$1'"
}

expect_log () {
    grep -qF -- "$1" "${FAKE_DOCKER_STATE}/docker.log" || fail "no '$1' in the docker calls"
}

expect_no_log () {
    ! grep -qF -- "$1" "${FAKE_DOCKER_STATE}/docker.log" || fail "unexpected '$1' in the docker calls"
}

end_scenario () {
    if [ "${FAILURES}" -ne "${FAILURES_BEFORE:-0}" ]; then
        echo "--- installer output (last 40 lines):"
        tail -n 40 "${OUT_FILE}"
        echo "--- docker calls:"
        cat "${FAKE_DOCKER_STATE}/docker.log"
    fi
    FAILURES_BEFORE=${FAILURES}
    echo "::endgroup::"
}

BASE_ARGS=(docker -ls true -off true -it community -dm standalone -noni true)

# The first run also installs the Homebrew formulae, which takes a while
new_scenario "Install with Docker Desktop stopped"
run_wrapper "${BASE_ARGS[@]}" -skiphc true
expect_rc 0
expect_output "Starting Docker Desktop"
expect_output "Thank you for installing"
expect_log "open /Applications/Docker.app"
expect_log "network create"
expect_log "-v onlyoffice_app_data:/volume"
expect_log " up -d"
[ -f "${SCENARIO_HOME}/onlyoffice/.env" ] || fail "no .env in ~/onlyoffice"
[ -f "${SCENARIO_HOME}/onlyoffice/docker-compose.yml" ] || fail "no docker-compose.yml in ~/onlyoffice"
grep -qE '^[[:space:]]*DOCKER_TAG=4[.]0[.]1$' "${SCENARIO_HOME}/onlyoffice/.env" || fail "DOCKER_TAG was not written to .env"
ls "${INSTALL_DIR}"/OneClick*.log > /dev/null 2>&1 && fail "the log file stays after a successful install"
end_scenario

new_scenario "Custom --basedir"
run_wrapper "${BASE_ARGS[@]}" -skiphc true -bd "${WORK_DIR}/custom/onlyoffice"
expect_rc 0
[ -f "${WORK_DIR}/custom/onlyoffice/.env" ] || fail "no .env in the custom base directory"
[ -e "${SCENARIO_HOME}/onlyoffice" ] && fail "the default directory was used"
end_scenario

new_scenario "A volumes directory is owned through a helper container"
mkdir -p "${SCENARIO_HOME}/data"
run_wrapper "${BASE_ARGS[@]}" -skiphc true -vd "${SCENARIO_HOME}/data"
expect_rc 0
expect_log "-v ${SCENARIO_HOME}/data/app_data:/volume"
expect_log "-v ${SCENARIO_HOME}/data/log_data:/volume"
grep -qE "^[[:space:]]*VOLUMES_DIR=\"?${SCENARIO_HOME}/data\"?$" "${SCENARIO_HOME}/onlyoffice/.env" || fail "VOLUMES_DIR was not written to .env"
[ -d "${SCENARIO_HOME}/data/app_data/Studio" ] || fail "no Studio directory in the volumes directory"
end_scenario

new_scenario "A busy port is detected with the BSD netstat"
# a plain listening socket: http.server of some Python versions leaves the socket shown as CLOSED by netstat
python3 -c "import socket, time; s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('0.0.0.0', 8080)); s.listen(5); time.sleep(120)" > /dev/null 2>&1 &
LISTENER_PID=$!
# no job notice about the process killed below
disown "${LISTENER_PID}"
for _ in 1 2 3 4 5; do netstat -an | grep -q '\.8080 .*LISTEN' && break; sleep 1; done
run_wrapper "${BASE_ARGS[@]}" -skiphc true -ep 8080
kill "${LISTENER_PID}" 2> /dev/null
expect_rc 1
expect_output "The following TCP Ports must be available: 8080"
expect_no_log " up -d"
end_scenario

new_scenario "Low Docker Desktop resources"
FAKE_DOCKER_MEM=3000000000 FAKE_DOCKER_CPU=2 run_wrapper "${BASE_ARGS[@]}"
expect_rc 1
expect_output "of RAM (available: 3000 MB)"
expect_output "Settings > Resources"
end_scenario

new_scenario "Running under sudo is refused"
if sudo -n true 2> /dev/null; then
    ( cd "${INSTALL_DIR}" && sudo -n env HOME="${SCENARIO_HOME}" FAKE_DOCKER_STATE="${FAKE_DOCKER_STATE}" PATH="${FAKE_BIN}:${PATH}" \
        bash apps-install.sh "${BASE_ARGS[@]}" -skiphc true < /dev/null ) > "${OUT_FILE}" 2>&1
    RC=$?
    expect_rc 1
    expect_output "without sudo"
else
    echo "skipped: sudo is not available"
fi
end_scenario

new_scenario "Options that macOS does not support are rejected"
run_wrapper docker -ls true -off true -it community -dm stack -noni true -skiphc true -led example.com -lem admin@example.com
expect_rc 1
expect_output "are supported on macOS only in the standalone deployment mode"
run_wrapper docker -ls true -off true -it community -dm microservices -noni true -skiphc true -cf /tmp/own.crt -ckf /tmp/own.key --certdomain example.com
expect_rc 1
expect_output "are supported on macOS only in the standalone deployment mode"
run_wrapper "${BASE_ARGS[@]}" -skiphc true -bd "${SCENARIO_HOME}"
expect_rc 1
expect_output "dedicated directory"
run_wrapper package
expect_rc 1
expect_output "Only the Docker installation is available on macOS"
end_scenario

new_scenario "Uninstall with Docker Desktop stopped starts it"
mkdir -p "${SCENARIO_HOME}/onlyoffice"
run_wrapper docker -ls true -off true -uni true -noni true
expect_rc 0
expect_log "open /Applications/Docker.app"
expect_log "network rm"
expect_output "completed"
end_scenario

new_scenario "Uninstall without Docker removes the local files and installs nothing"
if command -v docker > /dev/null 2>&1 || [ -x /Applications/Docker.app/Contents/Resources/bin/docker ]; then
    echo "skipped: Docker is installed on this machine"
else
    # A brew that refuses and records the installation of a cask, everything else goes to the real one
    NO_DOCKER_BIN="${WORK_DIR}/no-docker-bin"
    REAL_BREW=$(PATH="${PATH}:/opt/homebrew/bin:/usr/local/bin" command -v brew)
    mkdir -p "${NO_DOCKER_BIN}" "${SCENARIO_HOME}/onlyoffice"
    printf '#!/bin/bash\ncase "$*" in *--cask*) touch "%s/brew-cask"; exit 1 ;; esac\nexec "%s" "$@"\n' "${FAKE_DOCKER_STATE}" "${REAL_BREW}" > "${NO_DOCKER_BIN}/brew"
    chmod +x "${NO_DOCKER_BIN}/brew"
    ( cd "${INSTALL_DIR}" && printf 'n\n' | HOME="${SCENARIO_HOME}" FAKE_DOCKER_STATE="${FAKE_DOCKER_STATE}" PATH="${NO_DOCKER_BIN}:${PATH}" \
        bash apps-install.sh docker -ls true -off true -uni true -noni true ) > "${OUT_FILE}" 2>&1
    RC=$?
    expect_rc 0
    expect_output "Docker is not installed, only the local files"
    [ ! -e "${FAKE_DOCKER_STATE}/brew-cask" ] || fail "Docker Desktop was installed on uninstall"
    [ ! -e "${SCENARIO_HOME}/onlyoffice" ] || fail "the configuration directory was not removed"
fi
end_scenario

echo
if [ "${FAILURES}" -eq 0 ]; then
    echo "All scenarios passed"
else
    echo "${FAILURES} check(s) failed"
    exit 1
fi
