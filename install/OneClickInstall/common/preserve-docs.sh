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


prepare_docs_install() {
	PRODUCT_INSTALLED="false"
	DOCUMENT_SERVER_INSTALLED="false"
	DS_DEBCONF_PACKAGE=""

	for PACKAGE_NAME in "${package}" "${legacy_product}"; do
		package_installed "${PACKAGE_NAME}" || continue
		echo "${PACKAGE_NAME} $RES_APP_INSTALLED"
		PRODUCT_INSTALLED="true"
	done

	for DS_SUFFIX in "" "-de" "-ee"; do
		PACKAGE_NAME="${package_sysname}-documentserver${DS_SUFFIX}"
		package_installed "${PACKAGE_NAME}" || continue
		DS_INSTALLED_PKG_NAME="${PACKAGE_NAME}"
		echo "${DS_INSTALLED_PKG_NAME} $RES_APP_INSTALLED"
		DOCUMENT_SERVER_INSTALLED="true"
		command -v debconf-set-selections >/dev/null 2>&1 && DS_DEBCONF_PACKAGE="${DS_INSTALLED_PKG_NAME}"
		break
	done

	DS_CONF_FILE="/etc/${package_sysname}/documentserver/nginx/ds.conf"
	RESUME_DOCS_INSTALL=false
	if [ "${DOCUMENT_SERVER_INSTALLED}" = true ] && [ -f "${DS_CONF_FILE}.apps.install-pending" ]; then
		RESUME_DOCS_INSTALL=true
		UPDATE=true
		RECONFIGURE_PRODUCT=true
	fi

	if [ "$PRODUCT_INSTALLED" = "true" ] && [ "$UPDATE" != "true" ]; then
		echo "${product_name} is already installed. Use --update true to update."
		exit 0
	fi

	# Save the state before the first Apps installation, including --update on a host with Docs only.
	if [ "${DOCUMENT_SERVER_INSTALLED}" = true ] \
		&& { [ "${PRODUCT_INSTALLED}" = false ] || [ "${RESUME_DOCS_INSTALL}" = true ]; }; then
		DS_BACKUP_FILE="${DS_CONF_FILE}.apps.bak"
		if [ ! -f "${DS_BACKUP_FILE}" ]; then
			stat -Lc '%u %g %a' "/var/www/${package_sysname}/Data" > "${DS_CONF_FILE}.apps.data-access.bak.tmp"
			mv -f -- "${DS_CONF_FILE}.apps.data-access.bak.tmp" "${DS_CONF_FILE}.apps.data-access.bak"
			for PACKAGE_NAME in mysql-server mysql-community-server redis-server redis valkey rabbitmq-server; do
				if package_installed "${PACKAGE_NAME}"; then
					printf '%s\n' "${PACKAGE_NAME}"
				fi
			done > "${DS_CONF_FILE}.apps.dependencies.bak.tmp"
			mv -f -- "${DS_CONF_FILE}.apps.dependencies.bak.tmp" "${DS_CONF_FILE}.apps.dependencies.bak"
			cp -pL -- "${DS_CONF_FILE}" "${DS_BACKUP_FILE}.tmp"
			mv -f -- "${DS_BACKUP_FILE}.tmp" "${DS_BACKUP_FILE}"
		fi
		DOCS_RECONFIGURED=false
		trap finish_docs_install EXIT
		# Package installation can succeed before Apps configuration fails.
		touch "${DS_CONF_FILE}.apps.install-pending"
		if [ "${RESUME_DOCS_INSTALL}" = true ]; then
			systemctl stop "${product}-*.service" "${legacy_product}-*.service" >/dev/null 2>&1 || true
			restore_docs_configuration "${DS_CONF_FILE}" "${DS_DEBCONF_PACKAGE}" || exit 1
			restore_docs_data_access "${DS_CONF_FILE}" || exit 1
		fi
	fi
}

finish_docs_install() {
	local RESULT=$? RESTORE_FAILED=false
	if [ "${RESULT}" -ne 0 ] && [ "${DOCS_RECONFIGURED}" = true ]; then
		systemctl stop "${product}-*.service" "${legacy_product}-*.service" >/dev/null 2>&1 || true
		restore_docs_configuration "${DS_CONF_FILE}" "${DS_DEBCONF_PACKAGE}" || RESTORE_FAILED=true
		restore_docs_data_access "${DS_CONF_FILE}" || RESTORE_FAILED=true
		if [ "${RESTORE_FAILED}" = true ]; then
			echo "Could not restore Docs after the failed Apps installation; original backups have been retained." >&2
		fi
	elif [ "${RESULT}" -eq 0 ]; then
		rm -f -- "${DS_CONF_FILE}.apps.install-pending" || RESULT=$?
	fi
	if declare -F finish_debian_install >/dev/null; then
		finish_debian_install
	fi
	exit "${RESULT}"
}

prepare_docs_nginx() {
	local DS_LISTEN_ADDRESS
	# Move installed Docs off ports needed by Apps, inheriting HTTPS when possible.
	# Export these settings so package scripts can use them after this function returns.
	export INHERIT_SSL_DOMAIN="" INHERIT_SSL_CERT="" INHERIT_SSL_KEY="" INHERIT_SSL_INTERNAL_PORTAL=""
	if [ -n "$DS_INSTALLED_PKG_NAME" ]; then
		DS_CONF_FILE="/etc/${package_sysname}/documentserver/nginx/ds.conf"
		DS_BACKUP_FILE="${DS_CONF_FILE}.apps.bak"
		DS_CURRENT_PORT="$(grep -oP '^\s*listen\s+(\S*:)?\K\d+' "$DS_CONF_FILE" 2>/dev/null | head -1)"

		if { [ "${RESUME_DOCS_INSTALL}" = true ] || ! grep -q ssl_certificate "/etc/openresty/conf.d/${package_sysname}-proxy.conf" 2>/dev/null; } \
			&& grep -qE '^\s*listen\s+\S*:?443\b.*\bssl\b' "$DS_CONF_FILE" 2>/dev/null; then
			CANDIDATE_SSL_CERT="$(grep -oP '^\s*ssl_certificate\s+\K[^;]+' "$DS_CONF_FILE" | head -1)"
			CANDIDATE_SSL_KEY="$(grep -oP '^\s*ssl_certificate_key\s+\K[^;]+' "$DS_CONF_FILE" | head -1)"
			CANDIDATE_SSL_INTERNAL_PORTAL=""
			CANDIDATE_SSL_DOMAIN="$(grep -oP '^\s*server_name\s+\K\S+' "$DS_CONF_FILE" | grep -vE '^(_|localhost);?$|^\*\.' | head -1)"
			CANDIDATE_SSL_DOMAIN="${CANDIDATE_SSL_DOMAIN%;}"
			# Certificate names: subject CN first, then SAN (certificates from modern CAs have no CN).
			if [ -z "$CANDIDATE_SSL_DOMAIN" ] && [ -n "$CANDIDATE_SSL_CERT" ]; then
				CANDIDATE_CERT_NAMES="$({ openssl x509 -noout -subject -in "$CANDIDATE_SSL_CERT" 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' || true
					openssl x509 -noout -ext subjectAltName -in "$CANDIDATE_SSL_CERT" 2>/dev/null | grep -oP 'DNS:\K[^, ]+' || true; } | awk '!seen[$0]++')"
				CANDIDATE_WILDCARD="$(grep -m1 '^\*\.' <<< "$CANDIDATE_CERT_NAMES" || true)"
				if [ -z "$CANDIDATE_WILDCARD" ]; then
					CANDIDATE_SSL_DOMAIN="$(head -1 <<< "$CANDIDATE_CERT_NAMES")"
				else
					# A wildcard does not tell which host serves Docs and its apex may be absent from DNS: take a covered name that resolves.
					for CANDIDATE_HOST in "$(hostname -f 2>/dev/null || true)" $(grep -v '^\*\.' <<< "$CANDIDATE_CERT_NAMES"); do
						[ -n "$CANDIDATE_HOST" ] || continue
						{ grep -qxF "$CANDIDATE_HOST" <<< "$CANDIDATE_CERT_NAMES" || grep -qxF "*.${CANDIDATE_HOST#*.}" <<< "$CANDIDATE_CERT_NAMES"; } || continue
						timeout 5 getent hosts "$CANDIDATE_HOST" >/dev/null 2>&1 || continue
						CANDIDATE_SSL_DOMAIN="$CANDIDATE_HOST"; break
					done
					# No usable name: still inherit the certificate, the portal keeps its internal address.
					if [ -z "$CANDIDATE_SSL_DOMAIN" ]; then
						CANDIDATE_SSL_DOMAIN="${CANDIDATE_WILDCARD#\*.}"
						CANDIDATE_SSL_INTERNAL_PORTAL="true"
					fi
				fi
			fi

			# Compare public keys so ECDSA certs work too.
			if [ -n "$CANDIDATE_SSL_CERT" ] && [ -n "$CANDIDATE_SSL_KEY" ] && [ -n "$CANDIDATE_SSL_DOMAIN" ] \
				&& [[ "$CANDIDATE_SSL_DOMAIN" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] \
				&& openssl x509 -noout -in "$CANDIDATE_SSL_CERT" >/dev/null 2>&1 \
				&& CANDIDATE_SSL_CERT_PUBKEY="$(openssl x509 -noout -pubkey -in "$CANDIDATE_SSL_CERT" 2>/dev/null)" \
				&& [ -n "$CANDIDATE_SSL_CERT_PUBKEY" ] \
				&& [ "$CANDIDATE_SSL_CERT_PUBKEY" = "$(openssl pkey -pubout -passin pass: -in "$CANDIDATE_SSL_KEY" 2>/dev/null)" ]; then
				echo "${DS_INSTALLED_PKG_NAME} is serving HTTPS for ${CANDIDATE_SSL_DOMAIN}; ${product_name} will take over as the HTTPS front end with the same certificate."
				INHERIT_SSL_CERT="$CANDIDATE_SSL_CERT"; INHERIT_SSL_KEY="$CANDIDATE_SSL_KEY"; INHERIT_SSL_DOMAIN="$CANDIDATE_SSL_DOMAIN"; INHERIT_SSL_INTERNAL_PORTAL="$CANDIDATE_SSL_INTERNAL_PORTAL"
				[ -z "$INHERIT_SSL_INTERNAL_PORTAL" ] || echo "Note: the host name behind the wildcard certificate cannot be determined, so ${product_name} keeps its internal portal address; run 'apps-ssl-setup -f <domain> <certificate> <key>' afterwards to set the portal domain used in e-mails."
			else
				echo "Warning: ${DS_INSTALLED_PKG_NAME} looks HTTPS-configured but its certificate could not be verified; leaving it untouched and installing ${product_name} on plain HTTP (port ${APP_PORT:-80})." >&2
			fi
		fi

		if [ -n "$INHERIT_SSL_DOMAIN" ]; then
			DS_NEW_PORT="${DS_PORT:-8083}"
			if ss -H -lnt | awk '{print $4}' | grep -qE ":${DS_NEW_PORT}$"; then
				echo "Cannot move ${DS_INSTALLED_PKG_NAME} to port ${DS_NEW_PORT}: already in use."
				echo "$RES_CHECK_PORTS"
				exit 1
			fi
			# Older ss may omit process names; active nginx is enough after cert/key validation.
			PORT_443_OWNER="$(ss -H -lntp 2>/dev/null | grep -E ':443\s' | grep -oP 'users:\(\("\K[^"]+' | head -1)"
			if { [ -n "$PORT_443_OWNER" ] && [ "$PORT_443_OWNER" != "nginx" ]; } || { [ -z "$PORT_443_OWNER" ] && ! systemctl is-active --quiet nginx 2>/dev/null; }; then
				echo "Warning: cannot confirm port 443 is held by ${DS_INSTALLED_PKG_NAME}'s nginx; leaving its HTTPS configuration untouched." >&2
				INHERIT_SSL_DOMAIN=""; INHERIT_SSL_CERT=""; INHERIT_SSL_KEY=""
			fi

			DS_CONF_TMPL="/etc/${package_sysname}/documentserver/nginx/ds.conf.tmpl"
			SECURE_LINK_SECRET="$(grep -oP '(?<=secure_link_secret ).*(?=;)' "$DS_CONF_FILE" | head -1)"
			if [ -n "$INHERIT_SSL_DOMAIN" ] && [ -f "$DS_CONF_TMPL" ] && [ -n "$SECURE_LINK_SECRET" ]; then
				DOCS_RECONFIGURED=true
				echo "Switching ${DS_INSTALLED_PKG_NAME} to plain HTTP on 127.0.0.1:${DS_NEW_PORT}; ${product_name} inherits its HTTPS certificate for ${INHERIT_SSL_DOMAIN}."
				cp -f -- "$DS_CONF_TMPL" "$DS_CONF_FILE"
				SECURE_LINK_SECRET_ESC="$(printf '%s' "$SECURE_LINK_SECRET" | tr -d '\r\n' | sed 's/^"\(.*\)"$/\1/; s/[\\&|]/\\&/g')"
				sed -e "s|^[[:space:]]*set[[:space:]]\+\$secure_link_secret[[:space:]]\+.*;|  set \$secure_link_secret \"${SECURE_LINK_SECRET_ESC}\";|" \
					-e "s|listen 0\.0\.0\.0:80;|listen 127.0.0.1:${DS_NEW_PORT};|" \
					-e "s|listen \[::\]:80 default_server;|listen [::1]:${DS_NEW_PORT};|" -i "$DS_CONF_FILE"
				# Avoid IPv6 binds on hosts without ::1.
				{ [ -f /proc/net/if_inet6 ] && ip -6 addr show lo 2>/dev/null | grep -q '::1'; } || sed -i '/listen \[::1\]:/d' "$DS_CONF_FILE"

				# Guard against template format drift that sed would silently miss.
				if grep -qE '^\s*listen\s+(0\.0\.0\.0|\[::\]):80\b' "$DS_CONF_FILE"; then
					echo "Error: ${DS_CONF_TMPL} didn't match the expected format; restoring ${DS_INSTALLED_PKG_NAME}'s HTTPS configuration." >&2
					cp -f -- "${DS_BACKUP_FILE}" "$DS_CONF_FILE"
					INHERIT_SSL_DOMAIN=""; INHERIT_SSL_CERT=""; INHERIT_SSL_KEY=""
				elif command -v nginx >/dev/null 2>&1 && ! nginx -t >/dev/null 2>&1; then
					echo "Error: generated ${DS_CONF_FILE} failed nginx -t; restoring ${DS_INSTALLED_PKG_NAME}'s HTTPS configuration." >&2
					cp -f -- "${DS_BACKUP_FILE}" "$DS_CONF_FILE"
					INHERIT_SSL_DOMAIN=""; INHERIT_SSL_CERT=""; INHERIT_SSL_KEY=""
				else
					systemctl restart nginx 2>/dev/null || echo "Warning: failed to restart nginx after switching ${DS_INSTALLED_PKG_NAME} to HTTP; check its status manually." >&2
					timeout 5 bash -c "while ss -H -lnt | awk '{print \$4}' | grep -qE ':(80|443)\$'; do sleep 0.2; done" || true
				fi
			elif [ -n "$INHERIT_SSL_DOMAIN" ]; then
				echo "Warning: cannot find ${DS_CONF_TMPL} or its secure_link_secret; leaving ${DS_INSTALLED_PKG_NAME}'s HTTPS configuration untouched." >&2
				INHERIT_SSL_DOMAIN=""; INHERIT_SSL_CERT=""; INHERIT_SSL_KEY=""
			fi
		fi

		# Match only ports the final scan would otherwise flag as conflicts.
		DS_CONFLICT_PORTS=("${PRODUCT_PORTS[@]}" "${DEPENDENCY_PORTS[@]}")
		if [ -z "$INHERIT_SSL_DOMAIN" ] && [ -n "$DS_CURRENT_PORT" ] && printf '%s\n' "${DS_CONFLICT_PORTS[@]}" | grep -qxF "$DS_CURRENT_PORT"; then
			DS_NEW_PORT="${DS_PORT:-8083}"
			if [ "$DS_NEW_PORT" = "$DS_CURRENT_PORT" ]; then
				echo "Cannot move ${DS_INSTALLED_PKG_NAME} off port ${DS_CURRENT_PORT}: --dsport also resolves to it. Pass a different --dsport."
				exit 1
			fi
			if ss -H -lnt | awk '{print $4}' | grep -qE ":${DS_NEW_PORT}$"; then
				echo "Cannot move ${DS_INSTALLED_PKG_NAME} to port ${DS_NEW_PORT}: already in use."
				echo "$RES_CHECK_PORTS"
				exit 1
			fi
			echo "${DS_INSTALLED_PKG_NAME} is using port ${DS_CURRENT_PORT}, required by ${product_name}. Switching it to port ${DS_NEW_PORT}."
			DOCS_RECONFIGURED=true
			sed -i -E "s/(^[[:space:]]*listen[[:space:]]+(\S*:)?)${DS_CURRENT_PORT}([[:space:];])/\1${DS_NEW_PORT}\3/" "$DS_CONF_FILE"
			systemctl restart nginx 2>/dev/null || echo "Warning: failed to restart nginx after moving ${DS_INSTALLED_PKG_NAME} to port ${DS_NEW_PORT}; check its status manually." >&2
			timeout 5 bash -c "while ss -H -lnt | awk '{print \$4}' | grep -qE ':${DS_CURRENT_PORT}\$'; do sleep 0.2; done" || true
		fi
		if [ -n "${DS_DEBCONF_PACKAGE}" ] && [ "${DOCS_RECONFIGURED}" = true ]; then
			DS_LISTEN_ADDRESS=$(sed -nE 's/^[[:space:]]*listen[[:space:]]+([0-9.]+:[0-9]+)[[:space:];].*/\1/p' "${DS_CONF_FILE}" | head -1)
			[ -z "${DS_LISTEN_ADDRESS}" ] || printf '%s %s/listenaddress string %s\n' \
				"${DS_DEBCONF_PACKAGE}" "${DS_COMMON_NAME:-onlyoffice}" "${DS_LISTEN_ADDRESS}" | debconf-set-selections || exit 1
		fi
	fi

	# Clear nginx defaults left by interrupted installs before scanning ports.
	if [ -n "${DS_INSTALLED_PKG_NAME:-}" ]; then
		for NGINX_CONFIG in main:/etc/nginx/nginx.conf site:/etc/nginx/sites-enabled/default default:/etc/nginx/conf.d/default.conf; do
			NGINX_FILE="${NGINX_CONFIG#*:}"
			[ -e "${NGINX_FILE}" ] || continue
			[[ "${NGINX_CONFIG}" != main:* ]] || grep -q "server {" "${NGINX_FILE}" || continue
			DS_NGINX_BACKUP="${DS_CONF_FILE}.apps.nginx-${NGINX_CONFIG%%:*}.bak"
			if [ ! -e "${DS_NGINX_BACKUP}" ] && [ ! -L "${DS_NGINX_BACKUP}" ]; then
				cp -a -- "${NGINX_FILE}" "${DS_NGINX_BACKUP}.tmp"
				mv -f -- "${DS_NGINX_BACKUP}.tmp" "${DS_NGINX_BACKUP}"
			fi
		done
	fi
	NGINX_DEFAULT_SITE_DISABLED="false"
	if [ -e /etc/nginx/sites-enabled/default ]; then
		DOCS_RECONFIGURED=true
		if [ -n "${DS_INSTALLED_PKG_NAME:-}" ]; then
			rm -f -- /etc/nginx/sites-enabled/default
		else
			mv -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default.disabled
		fi
		NGINX_DEFAULT_SITE_DISABLED="true"
	fi
	if [ -f /etc/nginx/nginx.conf ] && grep -q "server {" /etc/nginx/nginx.conf; then
		DOCS_RECONFIGURED=true
		[ -n "${DS_INSTALLED_PKG_NAME:-}" ] || [ -f /etc/nginx/nginx.conf.bak ] || cp -f /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
		awk '/^[[:space:]]*server[[:space:]]*\{/&&!done{done=1;d=1;next}d{d+=gsub(/\{/,"{")-gsub(/\}/,"}");if(d<=0)d=0;next}1' \
			/etc/nginx/nginx.conf > /etc/nginx/nginx.conf.tmp && mv -f /etc/nginx/nginx.conf.tmp /etc/nginx/nginx.conf
		NGINX_DEFAULT_SITE_DISABLED="true"
	fi
	if [ -e /etc/nginx/conf.d/default.conf ]; then
		DOCS_RECONFIGURED=true
		if [ -n "${DS_INSTALLED_PKG_NAME:-}" ]; then
			rm -f -- /etc/nginx/conf.d/default.conf
		else
			mv -f /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
		fi
		NGINX_DEFAULT_SITE_DISABLED="true"
	fi
	if [ "$NGINX_DEFAULT_SITE_DISABLED" = "true" ]; then
		echo "Note: nginx default site disabled to free port ${APP_PORT:-80}."
		systemctl is-active --quiet nginx 2>/dev/null && { systemctl reload nginx 2>/dev/null || echo "Warning: failed to reload nginx after disabling its default site; check its status manually." >&2; }
		# Let old nginx workers release the socket before the port scan.
		timeout 5 bash -c "while ss -H -lnt | awk '{print \$4}' | grep -qE ':${APP_PORT:-80}\$'; do sleep 0.2; done" || true
	fi
}

restore_docs_configuration() (
    # Keep the trap and helpers local. Callers handle failure explicitly,
    # so every fallible step must be checked without relying on errexit.
    local DS_CONF_FILE="${1}"
    local DS_BACKUP_FILE="${DS_CONF_FILE}.apps.bak"
    local WORK DS_CERTIFICATE DS_CERT_NAME DS_RENEWAL_FILE NGINX_CONFIG I
    local OPENRESTY_ACTIVE=false OPENRESTY_ENABLED=false NGINX_ACTIVE=false
    local SERVICES_CHANGED=false ENABLEMENT_CHANGED=false
    local DEBCONF_PACKAGE="${2:-}" DS_LISTEN_ADDRESS=""
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
            echo "Docs restoration failed; original backups have been retained for retry." >&2
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
    elif [ -f "${DS_CONF_FILE}" ] \
        && [ "$(grep -vE '^[[:space:]]*#' "${DS_CONF_FILE}" | grep -oE '\bserver[[:space:]]*\{' | wc -l)" -eq 1 ] \
        && grep -qE '^[[:space:]]*listen[[:space:]]+(127\.0\.0\.1|0\.0\.0\.0):[0-9]+([[:space:]]+default_server)?[[:space:]]*;' "${DS_CONF_FILE}" \
        && ! grep -qE '^[[:space:]]*(ssl_certificate|listen[[:space:]].*[[:space:]]ssl)' "${DS_CONF_FILE}"; then
        # Fresh installations have no snapshot; expose the existing HTTP listener without changing its port.
        cp -pL -- "${DS_CONF_FILE}" "${WORK}/standalone.conf" || exit 1
        sed -i -E 's/(^[[:space:]]*listen[[:space:]]+)127\.0\.0\.1:/\10.0.0.0:/; s/(^[[:space:]]*listen[[:space:]]+)\[::1\]:/\1[::]:/' "${WORK}/standalone.conf" || exit 1
    else
        echo "Cannot keep Docs automatically: no original configuration was saved and the current configuration is not a standard HTTP setup." >&2
        exit 1
    fi
    DS_LISTEN_ADDRESS=$(sed -nE 's/^[[:space:]]*listen[[:space:]]+([0-9.]+:[0-9]+)[[:space:];].*/\1/p' "${WORK}/standalone.conf" | head -1)
    SOURCES+=("${WORK}/standalone.conf")

    for NGINX_CONFIG in main:/etc/nginx/nginx.conf site:/etc/nginx/sites-enabled/default default:/etc/nginx/conf.d/default.conf; do
        DS_BACKUP_FILE="${DS_CONF_FILE}.apps.nginx-${NGINX_CONFIG%%:*}.bak"
        if [ -e "${DS_BACKUP_FILE}" ] || [ -L "${DS_BACKUP_FILE}" ]; then
            TARGETS+=("${NGINX_CONFIG#*:}")
            SOURCES+=("${DS_BACKUP_FILE}")
        fi
    done

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

    # Remove Apps renewal jobs with the same rollback protection as the configs.
    TARGETS+=("/etc/cron.weekly/${product}-renew-letsencrypt" "/etc/cron.weekly/${legacy_product}-renew-letsencrypt"
        /etc/letsencrypt/renewal-hooks/deploy/onlyoffice-apps-openresty)
    SOURCES+=("" "" "")

    # Prepare the complete rollback set before changing any live file.
    for I in "${!TARGETS[@]}"; do
        if [ -e "${TARGETS[I]}" ] || [ -L "${TARGETS[I]}" ]; then
            cp -a -- "${TARGETS[I]}" "${WORK}/before.${I}" || exit 1
        fi
        [ -n "${SOURCES[I]}" ] || continue
        if [ -L "${SOURCES[I]}" ]; then
            cp -a -- "${SOURCES[I]}" "${TARGETS[I]}.apps.tmp" || exit 1
        else
            cp -pL -- "${SOURCES[I]}" "${TARGETS[I]}.apps.tmp" || exit 1
        fi
    done
    systemctl is-active --quiet nginx && NGINX_ACTIVE=true
    systemctl is-active --quiet openresty && OPENRESTY_ACTIVE=true
    systemctl is-enabled --quiet openresty && OPENRESTY_ENABLED=true

    for I in "${!TARGETS[@]}"; do
        TOUCHED+=("${I}")
        if [ -n "${SOURCES[I]}" ]; then
            mv -f -- "${TARGETS[I]}.apps.tmp" "${TARGETS[I]}" || exit 1
        else
            rm -f -- "${TARGETS[I]}" || exit 1
        fi
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
    if [ -n "${DS_LISTEN_ADDRESS}" ] && [ -n "${DEBCONF_PACKAGE}" ]; then
        printf 'SET %s/listenaddress %s\n' "${DS_COMMON_NAME:-onlyoffice}" "${DS_LISTEN_ADDRESS}" \
            | debconf-communicate "${DEBCONF_PACKAGE}" >/dev/null || exit 1
    fi
    exit 0
)

restore_docs_data_access() {
    local BACKUP="$1.apps.data-group.bak" DATA_GROUP DATA_UID DATA_GID DATA_MODE
    local DATA_DIR="/var/www/${package_sysname}/Data"
    if [ -f "$1.apps.data-access.bak" ]; then
        read -r DATA_UID DATA_GID DATA_MODE < "$1.apps.data-access.bak" || return 1
        # Package removal may delete the shared directory when it is empty.
        mkdir -p -- "${DATA_DIR}" || return 1
        chown "${DATA_UID}:${DATA_GID}" "${DATA_DIR}" || return 1
        chmod "${DATA_MODE}" "${DATA_DIR}" || return 1
    elif [ ! -d "${DATA_DIR}" ]; then
        mkdir -p -m 755 -- "${DATA_DIR}" || return 1
        chown ds:ds "${DATA_DIR}" || return 1
    fi
    if [ -f "${BACKUP}" ]; then
        while IFS= read -r DATA_GROUP; do
            if id "${package_sysname}" >/dev/null 2>&1 && id -nG "${package_sysname}" | tr ' ' '\n' | grep -qxF "${DATA_GROUP}"; then
                gpasswd -d "${package_sysname}" "${DATA_GROUP}" || return 1
            fi
        done < "${BACKUP}"
    fi
}
