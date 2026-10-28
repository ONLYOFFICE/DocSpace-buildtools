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


set -e

cat<<EOF

#######################################
#  CHECK PORTS
#######################################

EOF

PRODUCT_INSTALLED="false"
DOCUMENT_SERVER_INSTALLED="false"

package_installed() {
	if command -v dpkg-query >/dev/null 2>&1; then
		[ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = "installed" ]
	elif command -v rpm >/dev/null 2>&1; then
		rpm -q "$1" >/dev/null 2>&1
	else
		return 1
	fi
}

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
	break
done

if [ "$PRODUCT_INSTALLED" = "true" ] && [ "$UPDATE" != "true" ]; then
	echo "${product_name} is already installed. Use --update true to update."
	exit 0
fi

if [ "$UPDATE" != "true" ]; then
	if ! command -v ss >/dev/null 2>&1; then
		if command -v dpkg >/dev/null 2>&1; then
			apt-get install -yq iproute2
		elif command -v rpm >/dev/null 2>&1; then
			${package_manager} -y install iproute
		fi
	fi

	# Use the same port sets when relocating Docs and checking for conflicts.
	PRODUCT_PORTS=(
		"${APP_PORT:-80}" 5000 5001 5003 5004 5005 5006 5007 5009 5010 5011 5012 5013 5014 5015
		5027 5032 5033 5034 5075 5099 5100 5124 5157 5158
		8080 8081 8092 8888 9090 9834 9899 9999
	)
	DEPENDENCY_PORTS=()
	add_dependency_port() {
		local PORT="$1" PACKAGE_NAME
		shift
		for PACKAGE_NAME in "$@"; do
			if package_installed "${PACKAGE_NAME}"; then
				echo "${PACKAGE_NAME} $RES_APP_INSTALLED"
				return 0
			fi
		done
		DEPENDENCY_PORTS+=("${PORT}")
	}

	add_dependency_port "${MYSQL_SERVER_PORT:-3306}" mysql-server mysql-community-server
	add_dependency_port "${ELK_PORT:-9200}" opensearch

	if [ "$DOCUMENT_SERVER_INSTALLED" != "true" ]; then
		DEPENDENCY_PORTS+=("${DS_PORT:-8083}" 8000)
		# Debian and RPM distros use different PostgreSQL server package names.
		add_dependency_port 5432 "$(command -v dpkg-query >/dev/null 2>&1 && echo postgresql || echo postgresql-server)"
		add_dependency_port "${RABBITMQ_PORT:-5672}" rabbitmq-server
		add_dependency_port "${REDIS_PORT:-6379}" redis-server "${REDIS_PACKAGE:-redis}"
	fi

	if [ "${INSTALL_FLUENT_BIT}" = "true" ]; then
		add_dependency_port 5601 opensearch-dashboards
	fi

	# Move installed Docs off ports needed by Apps, inheriting HTTPS when possible.
	# export, not declare -x: this file is sourced from a function in the remote mode, where declare makes the variables local and the package scripts never see them.
	export INHERIT_SSL_DOMAIN="" INHERIT_SSL_CERT="" INHERIT_SSL_KEY="" INHERIT_SSL_INTERNAL_PORTAL=""
	if [ -n "$DS_INSTALLED_PKG_NAME" ]; then
		DS_CONF_FILE="/etc/${package_sysname}/documentserver/nginx/ds.conf"
		DS_CURRENT_PORT="$(grep -oP '^\s*listen\s+(\S*:)?\K\d+' "$DS_CONF_FILE" 2>/dev/null | head -1)"

		if ! grep -q ssl_certificate "/etc/openresty/conf.d/${package_sysname}-proxy.conf" 2>/dev/null \
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
				echo "Switching ${DS_INSTALLED_PKG_NAME} to plain HTTP on 127.0.0.1:${DS_NEW_PORT}; ${product_name} inherits its HTTPS certificate for ${INHERIT_SSL_DOMAIN}."
				cp -a -- "$DS_CONF_FILE" "${DS_CONF_FILE}.ssl.bak"
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
					cp -f -- "${DS_CONF_FILE}.ssl.bak" "$DS_CONF_FILE"
					INHERIT_SSL_DOMAIN=""; INHERIT_SSL_CERT=""; INHERIT_SSL_KEY=""
				elif command -v nginx >/dev/null 2>&1 && ! nginx -t >/dev/null 2>&1; then
					echo "Error: generated ${DS_CONF_FILE} failed nginx -t; restoring ${DS_INSTALLED_PKG_NAME}'s HTTPS configuration." >&2
					cp -f -- "${DS_CONF_FILE}.ssl.bak" "$DS_CONF_FILE"
					INHERIT_SSL_DOMAIN=""; INHERIT_SSL_CERT=""; INHERIT_SSL_KEY=""
				else
					{ command -v debconf-set-selections >/dev/null 2>&1 && echo "${DS_INSTALLED_PKG_NAME}" "${DS_COMMON_NAME:-onlyoffice}"/listenaddress string "127.0.0.1:${DS_NEW_PORT}" | debconf-set-selections; } || true
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
			sed -i -E "s/(^[[:space:]]*listen[[:space:]]+(\S*:)?)${DS_CURRENT_PORT}([[:space:];])/\1${DS_NEW_PORT}\3/" "$DS_CONF_FILE"
			DS_NEW_LISTENADDRESS="$(grep -oP '^\s*listen\s+\K[0-9]{1,3}(\.[0-9]{1,3}){3}(?=:'"${DS_NEW_PORT}"'\b)' "$DS_CONF_FILE" | head -1)"
			{ command -v debconf-set-selections >/dev/null 2>&1 && echo "${DS_INSTALLED_PKG_NAME}" "${DS_COMMON_NAME:-onlyoffice}"/listenaddress string "${DS_NEW_LISTENADDRESS:-0.0.0.0}:${DS_NEW_PORT}" | debconf-set-selections; } || true
			systemctl restart nginx 2>/dev/null || echo "Warning: failed to restart nginx after moving ${DS_INSTALLED_PKG_NAME} to port ${DS_NEW_PORT}; check its status manually." >&2
			timeout 5 bash -c "while ss -H -lnt | awk '{print \$4}' | grep -qE ':${DS_CURRENT_PORT}\$'; do sleep 0.2; done" || true
		fi
	fi

	# Clear nginx defaults left by interrupted installs before scanning ports.
	NGINX_DEFAULT_SITE_DISABLED="false"
	if [ -e /etc/nginx/sites-enabled/default ]; then
		mv -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default.disabled
		NGINX_DEFAULT_SITE_DISABLED="true"
	fi
	if [ -f /etc/nginx/nginx.conf ] && grep -q "server {" /etc/nginx/nginx.conf; then
		[ -f /etc/nginx/nginx.conf.bak ] || cp -f /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
		awk '/^[[:space:]]*server[[:space:]]*\{/&&!done{done=1;d=1;next}d{d+=gsub(/\{/,"{")-gsub(/\}/,"}");if(d<=0)d=0;next}1' \
			/etc/nginx/nginx.conf > /etc/nginx/nginx.conf.tmp && mv -f /etc/nginx/nginx.conf.tmp /etc/nginx/nginx.conf
		NGINX_DEFAULT_SITE_DISABLED="true"
	fi
	if [ -e /etc/nginx/conf.d/default.conf ]; then
		mv -f /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
		NGINX_DEFAULT_SITE_DISABLED="true"
	fi
	if [ "$NGINX_DEFAULT_SITE_DISABLED" = "true" ]; then
		echo "Note: nginx default site disabled to free port ${APP_PORT:-80}."
		systemctl is-active --quiet nginx 2>/dev/null && { systemctl reload nginx 2>/dev/null || echo "Warning: failed to reload nginx after disabling its default site; check its status manually." >&2; }
		# Let old nginx workers release the socket before the port scan.
		timeout 5 bash -c "while ss -H -lnt | awk '{print \$4}' | grep -qE ':${APP_PORT:-80}\$'; do sleep 0.2; done" || true
	fi

	# Claim 443 only when taking over an inherited certificate.
	[ -n "$INHERIT_SSL_DOMAIN" ] && PRODUCT_PORTS+=(443)

	USED_PORTS=""
	for PORT in $(printf "%s\n" "${PRODUCT_PORTS[@]}" "${DEPENDENCY_PORTS[@]}" | sort -n -u); do
		[[ "$PORT" =~ ^[0-9]+$ ]] || continue
		if ss -H -lnt | awk '{print $4}' | grep -qE ":${PORT}$"; then
			USED_PORTS="${USED_PORTS}${USED_PORTS:+, }${PORT}"
		fi
	done

	if [ -n "$USED_PORTS" ]; then
		echo "The following TCP ports are already in use: $USED_PORTS"
		echo "$RES_CHECK_PORTS"
		exit 1
	fi
fi
