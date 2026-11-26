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
#  INSTALL APP
#######################################

EOF
apt-get -y update

ds_pkg_name="${package_sysname}-documentserver"
case "${INSTALLATION_TYPE}" in
	"developer") ds_pkg_name+="-de" ;;
	"enterprise") ds_pkg_name+="-ee" ;;
esac

DS_COMMON_NAME=${DS_COMMON_NAME:-ds}
# Prints a value (dot path) from the config of a Docs installed on this host before, if that config is still there; node is an Apps prerequisite
get_saved_config_value() {
	local CONFIG_FILE SAVED_VALUE
	for CONFIG_FILE in "/etc/${package_sysname}/documentserver/local.json" "/etc/${package_sysname}/documentserver/local.json.rpmsave"; do
		[ -f "${CONFIG_FILE}" ] || continue
		SAVED_VALUE=$(CONFIG_FILE="${CONFIG_FILE}" VALUE_PATH="$1" node -e 'let value = JSON.parse(require("fs").readFileSync(process.env.CONFIG_FILE, "utf8")); for (const key of process.env.VALUE_PATH.split(".")) value = value == null ? undefined : value[key]; if (typeof value === "string") process.stdout.write(value)' 2>/dev/null) || true
		if [ -n "${SAVED_VALUE}" ]; then
			printf '%s\n' "${SAVED_VALUE}"
			return 0
		fi
	done
}

setup_postgres_db() {
	DS_DB_NAME=${DS_DB_NAME:-$DS_COMMON_NAME}
	DS_DB_USER=${DS_DB_USER:-$DS_COMMON_NAME}

	if ! su - postgres -s /bin/bash -c "psql -lqt" | cut -d \| -f 1 | grep -q "${DS_DB_NAME}"; then
		# A new Docs database gets its own password instead of the well-known default
		DS_DB_PWD=${DS_DB_PWD:-$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 24)}
		# The statement goes through stdin, so the password never appears in a command line
		su - postgres -s /bin/bash -c "psql -v ON_ERROR_STOP=1" <<< "CREATE USER ${DS_DB_USER} WITH password '${DS_DB_PWD//"'"/"''"}';"
		su - postgres -s /bin/bash -c "psql -c \"CREATE DATABASE ${DS_DB_NAME} OWNER ${DS_DB_USER};\""
	elif [ -z "${DS_DB_PWD}" ]; then
		# A kept database keeps the password of the Docs that used it, so reinstalling or switching the edition does not rotate it
		DS_DB_PWD=$(get_saved_config_value services.CoAuthoring.sql.dbPass)
		if [ -z "${DS_DB_PWD}" ] || ! PGPASSWORD="${DS_DB_PWD}" psql -h localhost -U "${DS_DB_USER}" -d "${DS_DB_NAME}" -w -c ';' >/dev/null 2>&1; then
			# Nothing else knows the password of a kept database without a working config, so the Docs installed now sets a fresh one
			DS_DB_PWD=$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 24)
			su - postgres -s /bin/bash -c "psql -v ON_ERROR_STOP=1" <<< "ALTER USER ${DS_DB_USER} WITH password '${DS_DB_PWD}';"
		fi
	fi

	# The password type keeps a secret preseeded before the templates exist in the root-only passwords.dat, not in the world-readable config.dat
	echo "${ds_pkg_name}" "$DS_COMMON_NAME"/db-pwd password "$DS_DB_PWD" | debconf-set-selections
	echo "${ds_pkg_name}" "$DS_COMMON_NAME"/db-user select "$DS_DB_USER" | debconf-set-selections
	echo "${ds_pkg_name}" "$DS_COMMON_NAME"/db-name select "$DS_DB_NAME" | debconf-set-selections
}

if [ "$UPDATE" = "true" ] && [ "$DOCUMENT_SERVER_INSTALLED" = "true" ] && [ "${PRESERVE_DOCS}" = false ]; then
	ds_pkg_installed_name=$(dpkg -l | awk -v pkg="${package_sysname}-documentserver" '$1=="ii" && index($2,pkg)==1{print $2}' | tail -n1)
    if [ -z "${ds_pkg_installed_name}" ]; then
        RECONFIGURE_PRODUCT="true"; DOCUMENT_SERVER_INSTALLED="false"
	elif [ -n "${ds_pkg_installed_name}" ] && [ "${ds_pkg_installed_name}" != "${ds_pkg_name}" ]; then
		apt-get remove -yq "${ds_pkg_installed_name}"
		RECONFIGURE_PRODUCT="true"; DOCUMENT_SERVER_INSTALLED="false"
	else
		apt-get install -y --only-upgrade "${ds_pkg_name}"
	fi
fi

# MySQL predates this run, so its root password was not set here.
if [ "${MYSQL_FIRST_TIME_INSTALL}" != "true" ] && [ "$PRODUCT_INSTALLED" = "false" ]; then
	# Probe MySQL over TCP, like the product does.
	MYSQL_PROBE_HOST=$([ "${MYSQL_SERVER_HOST}" = "localhost" ] && echo "127.0.0.1" || echo "${MYSQL_SERVER_HOST}")

	# A refused password still proves the server is up.
	mysql_responds() {
		local PING_OUTPUT
		PING_OUTPUT=$(mysqladmin -h "${MYSQL_PROBE_HOST}" -P "${MYSQL_SERVER_PORT}" -u "${MYSQL_SERVER_USER}" ping 2>&1) || true
		[[ "${PING_OUTPUT}" == *"alive"* || "${PING_OUTPUT}" == *"Access denied"* ]]
	}

	MYSQL_WAIT_DEADLINE=$((SECONDS + 60))
	until mysql_responds; do
		if [ "${SECONDS}" -ge "${MYSQL_WAIT_DEADLINE}" ]; then
			echo "ERROR: MySQL is already installed but does not answer on ${MYSQL_PROBE_HOST}:${MYSQL_SERVER_PORT}." >&2
			exit 1
		fi
		sleep 1
	done

	MYSQL_ARGS=(--connect-expired-password -h "${MYSQL_PROBE_HOST}" -P "${MYSQL_SERVER_PORT}" -u "${MYSQL_SERVER_USER}")
	# The password reaches the client through the environment, so it never appears in a command line; an empty one is not set at all, as before
	if ! { if [ -n "${MYSQL_SERVER_PASS}" ]; then MYSQL_PWD="${MYSQL_SERVER_PASS}" mysql "${MYSQL_ARGS[@]}" -e ";"; else mysql "${MYSQL_ARGS[@]}" -e ";"; fi; } >/dev/null 2>&1; then
		echo "ERROR: cannot connect to MySQL at ${MYSQL_PROBE_HOST}:${MYSQL_SERVER_PORT} as '${MYSQL_SERVER_USER}'." >&2
		echo "Pass a working password in the MYSQL_SERVER_PASS environment variable, or remove MySQL and run the installer again." >&2
		echo "Note: a '${MYSQL_SERVER_USER}' user authenticated by unix socket cannot be used, the product connects over TCP." >&2
		exit 1
	fi
fi

if [ "$DOCUMENT_SERVER_INSTALLED" = "false" ]; then
	DS_PORT=${DS_PORT:-8083}
	DS_JWT_ENABLED=${DS_JWT_ENABLED:-true}
	# Reinstalling or switching the edition keeps the JWT secret and header of the Docs installed before, so Apps keeps talking to it
	DS_JWT_SECRET=${DS_JWT_SECRET:-$(get_saved_config_value services.CoAuthoring.secret.inbox.string)}
	DS_JWT_SECRET=${DS_JWT_SECRET:-$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)}
	DS_JWT_HEADER=${DS_JWT_HEADER:-$(get_saved_config_value services.CoAuthoring.token.inbox.header)}
	DS_JWT_HEADER=${DS_JWT_HEADER:-AuthorizationJwt}

	echo "${ds_pkg_name}" "$DS_COMMON_NAME"/listenaddress string "127.0.0.1:${DS_PORT}" | debconf-set-selections
	echo "${ds_pkg_name}" "$DS_COMMON_NAME"/jwt-enabled select "${DS_JWT_ENABLED}" | debconf-set-selections
	echo "${ds_pkg_name}" "$DS_COMMON_NAME"/jwt-secret password "${DS_JWT_SECRET}" | debconf-set-selections
	echo "${ds_pkg_name}" "$DS_COMMON_NAME"/jwt-header select "${DS_JWT_HEADER}" | debconf-set-selections

	[ "$INSTALLATION_TYPE" != "community" ] && setup_postgres_db

	apt-get install -yq "${ds_pkg_name}"

	# Debian nginx enables a default site on port 80.
	[ -e /etc/nginx/sites-enabled/default ] && \
		mv -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default.disabled
	[ -e /etc/nginx/conf.d/default.conf ] && \
		mv -f /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
	echo "Note: nginx default sites disabled to avoid conflict with openresty."
	systemctl is-active --quiet nginx && systemctl reload nginx || systemctl start nginx
fi

if [ "$MAKESWAP" == "true" ]; then
	make_swap "/${product}_swapfile"
fi

if [ "$PRODUCT_INSTALLED" = "false" ]; then
	echo "${package}" "${package}"/db-host select "$MYSQL_SERVER_HOST" | debconf-set-selections
	echo "${package}" "${package}"/db-port select "$MYSQL_SERVER_PORT" | debconf-set-selections
	echo "${package}" "${package}"/db-name select "$MYSQL_SERVER_DB_NAME" | debconf-set-selections
	echo "${package}" "${package}"/db-user select "$MYSQL_SERVER_USER" | debconf-set-selections
	echo "${package}" "${package}"/db-pwd password "$MYSQL_SERVER_PASS" | debconf-set-selections

	APP_INSTALL_STATUS=0
	apt-get "${DOCS_APT_OPTIONS[@]}" install -y "${package}${PRODUCT_VERSION:+*=${PRODUCT_VERSION}}" || APP_INSTALL_STATUS=$?
	# Upgrades read the database settings from the configuration files, so the administrative credentials are dropped whatever the result
	# The second pass rewrites config.dat once more, so its config.dat-old backup no longer holds a value preseeded by an earlier run
	DEBCONF_CLEAR_COMMANDS="SET ${package}/db-host\nSET ${package}/db-name\nSET ${package}/db-user\nSET ${package}/db-pwd\nSET ${package}/db-port\n"
	printf "${DEBCONF_CLEAR_COMMANDS}" | debconf-communicate "${package}" >/dev/null || true
	printf "${DEBCONF_CLEAR_COMMANDS}" | debconf-communicate "${package}" >/dev/null || true
	if [ "${APP_INSTALL_STATUS}" -ne 0 ]; then
		echo "Error: installation of ${package} failed."
		exit 1
	fi
elif [ "$UPDATE" = "true" ] && [ "$PRODUCT_INSTALLED" = "true" ]; then
	CURRENT_VERSION=$(dpkg-query -W -f='${Version}' "${package}" 2>/dev/null) || true
	AVAILABLE_VERSIONS=$(apt show "${package}" 2>/dev/null | grep -E '^Version:' | awk '{print $2}')
	if [ -z "${CURRENT_VERSION}" ]; then # (DS v4.0.0) take over an installation made before the rename to ONLYOFFICE Apps
		apt-get "${DOCS_APT_OPTIONS[@]}" install -o DPkg::options::="--force-confnew" -y "${package}" opensearch="${OPENSEARCH_VERSION}"
	elif [[ "$AVAILABLE_VERSIONS" != *"$CURRENT_VERSION"* ]]; then
		apt-get "${DOCS_APT_OPTIONS[@]}" install -o DPkg::options::="--force-confnew" -y --only-upgrade "${package}" opensearch="${OPENSEARCH_VERSION}"
	elif [ "${RECONFIGURE_PRODUCT}" = "true" ]; then
		DEBIAN_FRONTEND=noninteractive dpkg-reconfigure "${package}"
	fi
fi

echo ""
echo "$RES_INSTALL_SUCCESS"
echo "$RES_QUESTIONS"
echo ""
