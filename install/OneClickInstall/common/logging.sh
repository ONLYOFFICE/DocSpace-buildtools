#!/bin/bash

 #
 # Copyright (C) Ascensio System SIA, 2009-2026
 #
 # This program is a free software product. You can redistribute it and/or
 # modify it under the terms of the GNU Affero General Public License (AGPL)
 # version 3 as published by the Free Software Foundation, together with the
 # additional terms provided in the LICENSE file.
 #
 # This program is distributed WITHOUT ANY WARRANTY; without even the implied
 # warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. For
 # details, see the GNU AGPL at: https://www.gnu.org/licenses/agpl-3.0.html
 #
 # You can contact Ascensio System SIA by email at info@onlyoffice.com
 # or by postal mail at 20A-6 Ernesta Birznieka-Upisha Street, Riga,
 # LV-1050, Latvia, European Union.
 #
 # The interactive user interfaces in modified versions of the Program
 # are required to display Appropriate Legal Notices in accordance with
 # Section 5 of the GNU AGPL version 3.
 #
 # No trademark rights are granted under this License.
 #
 # All non-code elements of the Product, including illustrations,
 # icon sets, and technical writing content, are licensed under the
 # Creative Commons Attribution-ShareAlike 4.0 International License:
 # https://creativecommons.org/licenses/by-sa/4.0/legalcode
 #
 # This license applies only to such non-code elements and does not
 # modify or replace the licensing terms applicable to the Program's
 # source code, which remains licensed under the GNU Affero General
 # Public License v3.
 #
 # SPDX-License-Identifier: AGPL-3.0-only
 #


# Installer output logging for apps-install.sh; keep it bash 3.2 compatible (macOS runs the wrapper under the system bash) and safe under set -e

# Writes the host details support asks about first; every probe is best effort
log_environment_summary () {
    local OS_NAME CPU_COUNT MEMORY DOCKER_VERSION COMPOSE_VERSION
    if [[ "$OSTYPE" == darwin* ]]; then
        OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null)"
        CPU_COUNT=$(sysctl -n hw.ncpu 2>/dev/null)
        MEMORY="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1048576 )) MB total"
    else
        OS_NAME=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${ID} ${VERSION_ID}}")
        CPU_COUNT=$(nproc --all 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null)
        MEMORY=$(awk '/^MemTotal:/ {total = $2} /^MemAvailable:/ {free = $2} /^SwapTotal:/ {swap = $2}
            END {printf "%d MB total, %d MB available, %d MB swap", total / 1024, free / 1024, swap / 1024}' /proc/meminfo 2>/dev/null)
    fi
    if command -v docker >/dev/null 2>&1; then
        DOCKER_VERSION=$(docker info --format '{{.ServerVersion}}' 2>/dev/null)
        [ -n "${DOCKER_VERSION}" ] || DOCKER_VERSION="$(docker --version 2>/dev/null), daemon not reachable"
        COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || docker-compose version --short 2>/dev/null)
    fi
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "OS: ${OS_NAME:-unknown}, $(uname -m), kernel $(uname -r)"
    echo "CPU: ${CPU_COUNT:-unknown} cores; RAM: ${MEMORY:-unknown}"
    echo "Disk: $(df -Pk / 2>/dev/null | awk 'NR == 2 {printf "%d GB free of %d GB on /", $4 / 1048576, $2 / 1048576}')"
    echo "Docker: ${DOCKER_VERSION:-not installed}; Compose: ${COMPOSE_VERSION:-not installed}"
}

# Creates LOG_FILE readable by root only, headed by the command line with secret values masked and the host summary
start_log () {
    local MASK_NEXT="false" PARAMETER
    local MASKED_PARAMETERS=()
    for PARAMETER in "${@:2}"; do
        if [ "$MASK_NEXT" = "true" ]; then MASKED_PARAMETERS+=("***"); MASK_NEXT="false"; continue; fi
        case "$PARAMETER" in
            -p | --password | -mysqlrp | --mysqlrootpassword | -mysqlp | --mysqlpassword | -mk | --machinekey | -js | --jwtsecret | \
            -rdspass | --redispassword | -rbtpass | --rabbitmqpassword | -dp | --dashboardspassword ) MASK_NEXT="true" ;;
        esac
        MASKED_PARAMETERS+=("$PARAMETER")
    done
    LOG_FILE="${PWD%/}/OneClick$(basename "${1%.sh}")_$(date +%Y%m%d_%H%M%S).log"
    ( umask 077 && { echo "Command: bash $1 ${MASKED_PARAMETERS[*]}"; log_environment_summary; } > "${LOG_FILE}" ) \
        || { echo "Failed to create log file" >&2; exit 1; }
}

# Runs "bash <script> [parameters]" with its output saved to LOG_FILE and sets EXIT_CODE
run_with_log () {
    if [[ "$OSTYPE" != darwin* ]] && [ -t 0 ] && ! command -v script >/dev/null 2>&1 && command -v dnf >/dev/null 2>&1; then
        dnf -y install util-linux-script || true
    fi
    start_log "$@"
    # tee where script(1) does not fit: BSD script has no -c, and with piped answers script would turn stdin into a terminal
    if [[ "$OSTYPE" == darwin* ]] || [ ! -t 0 ] || ! command -v script >/dev/null 2>&1; then
        bash "$@" 2>&1 | tee -a "${LOG_FILE}"
        EXIT_CODE=${PIPESTATUS[0]}
        return
    fi
    # script writes its command into the log header, so the parameters with secrets reach it through the environment
    local OCI_COMMAND
    printf -v OCI_COMMAND '%q ' bash "$@"
    OCI_COMMAND="${OCI_COMMAND}" script -q -e -a "${LOG_FILE}" -c 'COMMAND=$OCI_COMMAND; unset OCI_COMMAND; exec bash -c "$COMMAND"' && EXIT_CODE=0 || EXIT_CODE=$?
}

# Removes the log after a successful run, otherwise compacts it and tells where it is
finish_log () {
    [ -n "${LOG_FILE}" ] || return 0
    if [ "${EXIT_CODE:-0}" -eq 0 ]; then
        rm -f "${LOG_FILE}"
        return 0
    fi
    compact_log "${LOG_FILE}"
    echo -e "\033[0;31mAn error occurred while executing the script. Log saved to: ${LOG_FILE}\033[0m"
}

# Replays carriage returns and cursor movements, so the saved log holds the final screen instead of every frame of progress bars and spinners
compact_log () {
    if ( umask 077 && LC_ALL=C awk '
        BEGIN { ESC = "\033"; CONTROL = "[\r\b" ESC "]"; top = row = col = 0 }
        function emit(line) {
            sub(/[ \t]+$/, "", line)
            if (line != "" && line == last) { repeats++; return }
            if (repeats) print "[previous line repeated " repeats " more times]"
            repeats = 0
            if (line == "" && last == "") return
            print line; last = line
        }
        function flush(limit,   index_row) {
            for (index_row = top; index_row < limit; index_row++) { emit(buf[index_row]); delete buf[index_row] }
            top = limit
        }
        function put(text,   line, size) {
            if (detached || text == "") return
            line = buf[row]; size = length(line)
            if (size < col) { line = line sprintf("%" (col - size) "s", ""); size = col }
            buf[row] = substr(line, 1, col) text substr(line, col + length(text) + 1)
            col += length(text)
            if (row >= rows) rows = row + 1
        }
        function csi(params, final,   count) {
            count = params + 0; if (count < 1) count = 1
            if (final == "A" || final == "F") { row -= count; if (row < top) row = top; if (final == "F") col = 0 }
            else if (final == "B" || final == "E") { row += count; if (final == "E") col = 0 }
            else if (final == "C") col += count
            else if (final == "D") { col -= count; if (col < 0) col = 0 }
            else if (final == "G") col = params + 0 > 0 ? params - 1 : 0
            else if (final == "K") { if (params == "2") buf[row] = ""; else if (params == "" || params == "0") buf[row] = substr(buf[row], 1, col) }
            else if (final == "H" || final == "f") { if (saved) detached = 1 }
            else if (final == "s") save()
            else if (final == "u") restore()
        }
        # Text drawn between a cursor save and restore is a status line (dpkg progress bar), not part of the output
        function save() { saved = 1; saved_row = row; saved_col = col }
        function restore() { if (saved) { row = saved_row; col = saved_col }; saved = detached = 0 }
        {
            rest = $0
            while (rest != "") {
                if (!match(rest, CONTROL)) { put(rest); break }
                put(substr(rest, 1, RSTART - 1))
                char = substr(rest, RSTART, 1); rest = substr(rest, RSTART + 1)
                if (char == "\r") col = 0
                else if (char == "\b") { if (col > 0) col-- }
                else if (match(rest, /^\[[0-9;?<=>]*[@-~]/)) { csi(substr(rest, 2, RLENGTH - 2), substr(rest, RLENGTH, 1)); rest = substr(rest, RLENGTH + 1) }
                else if (match(rest, "^][^\007]*(\007|" ESC "\\\\)")) rest = substr(rest, RLENGTH + 1)
                else if (substr(rest, 1, 1) == "7") { save(); rest = substr(rest, 2) }
                else if (substr(rest, 1, 1) == "8") { restore(); rest = substr(rest, 2) }
                else if (match(rest, /^[()][0-9A-Za-z]/)) rest = substr(rest, 3)
                else rest = substr(rest, 2)
            }
            # A status line never spans lines, so a newline ends a save that was never restored
            if (detached) restore()
            row++; col = 0
            # Rows far above the cursor can no longer be redrawn, so they are written out to keep memory flat
            if (row - top > 1000) flush(row - 500)
        }
        # An interrupted redraw can leave the cursor above rows that are still on the screen
        END { flush(rows > row ? rows : row); if (repeats) print "[previous line repeated " repeats " more times]" }
    ' "$1" > "$1.tmp" ); then mv -f "$1.tmp" "$1"; else rm -f "$1.tmp"; fi
}
