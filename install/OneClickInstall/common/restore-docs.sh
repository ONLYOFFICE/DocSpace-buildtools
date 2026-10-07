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


restore_docs_configuration() (
    # Keep the trap and helpers local. Callers handle failure explicitly,
    # so every fallible step must be checked without relying on errexit.
    local DS_CONF_FILE="${1}"
    local DS_BACKUP_FILE="${DS_CONF_FILE}.apps.bak"
    local WORK DS_CURRENT_PORT DS_CERTIFICATE DS_CERT_NAME DS_RENEWAL_FILE I
    local OPENRESTY_ACTIVE=false OPENRESTY_ENABLED=false NGINX_ACTIVE=false
    local SERVICES_CHANGED=false ENABLEMENT_CHANGED=false
    local -a TARGETS=("${DS_CONF_FILE}") SOURCES=() TOUCHED=()

    WORK=$(mktemp -d "${DS_CONF_FILE}.apps.restore.XXXXXX") || return 1
    finish_restore() {
        local RESULT=$? INDEX ROLLBACK_FAILED=false
        if [ "${RESULT}" -ne 0 ]; then
            for ((INDEX=${#TOUCHED[@]}-1; INDEX>=0; INDEX--)); do
                I=${TOUCHED[INDEX]}
                if [ -e "${WORK}/before.${I}" ] || [ -L "${WORK}/before.${I}" ]; then
                    mv -f -- "${WORK}/before.${I}" "${TARGETS[I]}" || ROLLBACK_FAILED=true
                else
                    rm -f -- "${TARGETS[I]}" || ROLLBACK_FAILED=true
                fi
            done
            if [ "${SERVICES_CHANGED}" = true ]; then
                if [ "${NGINX_ACTIVE}" = true ]; then
                    systemctl restart nginx || ROLLBACK_FAILED=true
                else
                    systemctl stop nginx || ROLLBACK_FAILED=true
                fi
                if [ "${ENABLEMENT_CHANGED}" = true ]; then
                    systemctl enable openresty || ROLLBACK_FAILED=true
                fi
                if [ "${OPENRESTY_ACTIVE}" = true ]; then
                    systemctl start openresty || ROLLBACK_FAILED=true
                fi
            fi
            echo "Cannot restore standalone Docs; Apps has not been removed." >&2
        fi
        for I in "${!TARGETS[@]}"; do
            rm -f -- "${TARGETS[I]}.apps.tmp" || true
        done
        if [ "${ROLLBACK_FAILED}" = true ]; then
            echo "Rollback incomplete. Recovery files are in ${WORK}; check nginx and openresty before retrying." >&2
        else
            rm -rf -- "${WORK}"
        fi
        return "${RESULT}"
    }
    trap finish_restore EXIT

    [ -f "${DS_BACKUP_FILE}" ] || DS_BACKUP_FILE="${DS_CONF_FILE}.ssl.bak"
    if [ -f "${DS_BACKUP_FILE}" ]; then
        cp -pL -- "${DS_BACKUP_FILE}" "${WORK}/standalone.conf" || exit 1
    else
        # Fresh Apps installs and older installations have no original snapshot.
        # This fallback exposes HTTP; it cannot reconstruct a previous custom setup.
        echo "No original Docs snapshot; using the standalone HTTP fallback." >&2
        cp -pL -- "${DS_CONF_FILE}" "${WORK}/standalone.conf" || exit 1
        local DS_SSL_LISTEN_PATTERN='^[[:space:]]*listen[[:space:]]+[^;]*[[:space:]](ssl|quic)([[:space:];]|$)'
        DS_CURRENT_PORT="$(sed -nE "s/#.*//; /${DS_SSL_LISTEN_PATTERN}/!s/^[[:space:]]*listen[[:space:]]+([^[:space:];]+:)?([0-9]+)([[:space:];]).*/\2/p" "${DS_CONF_FILE}" | head -1)"
        if [ -n "${DS_CURRENT_PORT}" ]; then
            sed -i -E \
                -e "/${DS_SSL_LISTEN_PATTERN}/b" \
                -e "s#^([[:space:]]*)listen[[:space:]]+${DS_CURRENT_PORT}([[:space:];])#\1listen 0.0.0.0:80\2#" \
                -e "s#^([[:space:]]*)listen[[:space:]]+(127\.0\.0\.1|0\.0\.0\.0):${DS_CURRENT_PORT}([[:space:];])#\1listen 0.0.0.0:80\3#" \
                -e "s#^([[:space:]]*)listen[[:space:]]+\[::1?\]:${DS_CURRENT_PORT}([[:space:];])#\1listen [::]:80\2#" "${WORK}/standalone.conf" || exit 1
        elif ! grep -qE "${DS_SSL_LISTEN_PATTERN}" "${DS_CONF_FILE}"; then
            echo "Cannot determine the Docs port." >&2
            exit 1
        fi
    fi
    SOURCES+=("${WORK}/standalone.conf")

    DS_CERTIFICATE="$(grep -oP '^\s*ssl_certificate\s+\K[^;]+' "${WORK}/standalone.conf" | head -1 || true)"
    if [[ "${DS_CERTIFICATE}" == /etc/letsencrypt/live/*/fullchain.pem ]]; then
        DS_CERT_NAME="$(basename "$(dirname "${DS_CERTIFICATE}")")" || exit 1
        DS_RENEWAL_FILE="/etc/letsencrypt/renewal/${DS_CERT_NAME}.conf"
        DS_BACKUP_FILE="${DS_CONF_FILE}.apps.${DS_CERT_NAME}.conf.bak"
        if [ -f "${DS_BACKUP_FILE}" ]; then
            for DS_RENEWAL_FILE in /etc/cron.d/letsencrypt /usr/bin/letsencrypt_cron.sh "${DS_RENEWAL_FILE}"; do
                DS_BACKUP_FILE="${DS_CONF_FILE}.apps.$(basename "${DS_RENEWAL_FILE}").bak" || exit 1
                if [ -f "${DS_BACKUP_FILE}" ]; then
                    TARGETS+=("${DS_RENEWAL_FILE}")
                    SOURCES+=("${DS_BACKUP_FILE}")
                fi
            done
        elif grep -qE '/var/www/onlyoffice/(apps|docspace)' "${DS_RENEWAL_FILE}" 2>/dev/null; then
            echo "No original renewal configuration for ${DS_CERT_NAME}. Restore it manually before removing Apps." >&2
            exit 1
        fi
    fi

    # Prepare the complete rollback set before changing any live file.
    for I in "${!TARGETS[@]}"; do
        if [ -e "${TARGETS[I]}" ] || [ -L "${TARGETS[I]}" ]; then
            cp -a -- "${TARGETS[I]}" "${WORK}/before.${I}" || exit 1
        fi
        cp -pL -- "${SOURCES[I]}" "${TARGETS[I]}.apps.tmp" || exit 1
    done
    systemctl is-active --quiet nginx && NGINX_ACTIVE=true
    systemctl is-active --quiet openresty && OPENRESTY_ACTIVE=true
    systemctl is-enabled --quiet openresty && OPENRESTY_ENABLED=true

    for I in "${!TARGETS[@]}"; do
        TOUCHED+=("${I}")
        mv -f -- "${TARGETS[I]}.apps.tmp" "${TARGETS[I]}" || exit 1
    done
    nginx -t || exit 1
    SERVICES_CHANGED=true
    if [ "${OPENRESTY_ACTIVE}" = true ]; then
        systemctl stop openresty || exit 1
    fi
    systemctl restart nginx || exit 1
    if [ "${OPENRESTY_ENABLED}" = true ]; then
        ENABLEMENT_CHANGED=true
        systemctl disable openresty || exit 1
    fi
    exit 0
)
