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

if command -v dpkg >/dev/null 2>&1; then
	PKG_LIST="$(dpkg -l)"
elif command -v rpm >/dev/null 2>&1; then
	PKG_LIST="$(rpm -qa)"
fi

for PACKAGE_NAME in "${package}" "${legacy_product}"; do
	if command -v dpkg-query >/dev/null 2>&1; then
		[ "$(dpkg-query -W -f='${db:Status-Status}' "${PACKAGE_NAME}" 2>/dev/null)" = "installed" ] || continue
	elif command -v rpm >/dev/null 2>&1; then
		rpm -q "${PACKAGE_NAME}" >/dev/null 2>&1 || continue
	else
		continue
	fi
	echo "${PACKAGE_NAME} $RES_APP_INSTALLED"
	PRODUCT_INSTALLED="true"
done

DS_INSTALLED_PKG_NAME="$(grep -oE "${package_sysname}-documentserver(-de|-ee)?" <<< "$PKG_LIST" | head -1)"
if [ -n "$DS_INSTALLED_PKG_NAME" ]; then
	echo "${DS_INSTALLED_PKG_NAME} $RES_APP_INSTALLED"
	DOCUMENT_SERVER_INSTALLED="true"
fi

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

	# An already-installed Document Server may be using the port ${product_name}'s own web front-end needs; move it out of the way instead of failing.
	if [ "$DOCUMENT_SERVER_INSTALLED" = "true" ] && [ -n "$DS_INSTALLED_PKG_NAME" ]; then
		DS_CONF_FILE="/etc/${package_sysname}/documentserver/nginx/ds.conf"
		DS_CURRENT_PORT="$(grep -oP '^\s*listen\s+(\S*:)?\K\d+' "$DS_CONF_FILE" 2>/dev/null | head -1)"
		if [ -n "$DS_CURRENT_PORT" ] && [ "$DS_CURRENT_PORT" = "${APP_PORT:-80}" ]; then
			DS_NEW_PORT="${DS_PORT:-8083}"
			if ss -H -lnt | awk '{print $4}' | grep -qE ":${DS_NEW_PORT}$"; then
				echo "Cannot move ${DS_INSTALLED_PKG_NAME} to port ${DS_NEW_PORT}: already in use."
				echo "$RES_CHECK_PORTS"
				exit 1
			fi
			echo "${DS_INSTALLED_PKG_NAME} is using port ${DS_CURRENT_PORT}, required by ${product_name}. Switching it to port ${DS_NEW_PORT}."
			sed -i "/^\s*listen/ s/:${DS_CURRENT_PORT}\([[:space:];]\)/:${DS_NEW_PORT}\1/" "$DS_CONF_FILE"
			{ command -v debconf-set-selections >/dev/null 2>&1 && echo "${DS_INSTALLED_PKG_NAME}" "${DS_COMMON_NAME:-onlyoffice}"/ds-port select "$DS_NEW_PORT" | debconf-set-selections; } || true
			systemctl restart nginx 2>/dev/null || true
			timeout 5 bash -c "while ss -H -lnt | awk '{print \$4}' | grep -qE ':${DS_CURRENT_PORT}\$'; do sleep 0.2; done" || true
		fi
	fi

	PRODUCT_PORTS=(
		"${APP_PORT:-80}" 5000 5001 5003 5004 5005 5006 5007 5009 5010 5011 5012 5013 5014 5015
		5027 5032 5033 5034 5075 5099 5100 5124 5157 5158
		8080 8081 8092 9090 9834 9899
	)

	DEPENDENCY_PORTS=(
		"${MYSQL_SERVER_PORT:-3306}"
		"${ELK_PORT:-9200}"
	)

	if [ "$DOCUMENT_SERVER_INSTALLED" != "true" ]; then
		DEPENDENCY_PORTS+=(
			"${DS_PORT:-8083}" 8000 5432
			"${RABBITMQ_PORT:-5672}" "${REDIS_PORT:-6379}"
		)
	fi

	[ "${INSTALL_FLUENT_BIT}" = "true" ] && DEPENDENCY_PORTS+=(5601)

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
