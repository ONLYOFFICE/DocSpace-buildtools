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

for SVC in $package_services; do
		systemctl start $SVC
		[ "${PRESERVE_DOCS}" = true ] || systemctl enable $SVC
done

ds_pkg_name="${package_sysname}-documentserver"
case "${INSTALLATION_TYPE}" in
	"developer") ds_pkg_name+="-de" ;;
	"enterprise") ds_pkg_name+="-ee" ;;
esac

DS_COMMON_NAME=${DS_COMMON_NAME:-ds}
setup_postgres_db() {
	DS_DB_NAME=${DS_DB_NAME:-$DS_COMMON_NAME}
	DS_DB_USER=${DS_DB_USER:-$DS_COMMON_NAME}

	if ! su - postgres -s /bin/bash -c "psql -lqt" | cut -d \| -f 1 | grep -q "${DS_DB_NAME}"; then
		# A new Docs database gets its own password instead of the well-known default
		DS_DB_PWD=${DS_DB_PWD:-$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 24)}
		su - postgres -s /bin/bash -c "psql -c \"CREATE USER ${DS_DB_USER} WITH password '${DS_DB_PWD}';\""
		su - postgres -s /bin/bash -c "psql -c \"CREATE DATABASE ${DS_DB_NAME} OWNER ${DS_DB_USER};\""
	elif [ -z "${DS_DB_PWD}" ]; then
		# A kept database may hold a random password stored nowhere, so the Docs installed now sets a fresh one
		DS_DB_PWD=$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 24)
		su - postgres -s /bin/bash -c "psql -c \"ALTER USER ${DS_DB_USER} WITH password '${DS_DB_PWD}';\""
	fi
}

# True when a package other than Docs still records /etc/onlyoffice with an owner other than root:root
config_dir_held_by_older_package() {
	local CONFIG_DIR="/etc/${package_sysname}" OWNERS OWNER
	OWNERS=$(rpm -qf --qf '%{NAME}\n' "${CONFIG_DIR}" 2>/dev/null) || return 1
	for OWNER in ${OWNERS}; do
		[[ "${OWNER}" == "${package_sysname}"-documentserver* ]] && continue
		rpm -q --dump "${OWNER}" | awk -v dir="${CONFIG_DIR}" '$1 == dir && ($6 != "root" || $7 != "root") { found = 1 } END { exit !found }' && return 0
	done
	return 1
}

DS_UPDATE_DEFERRED="false"
if [ "$UPDATE" = "true" ] && [ "$DOCUMENT_SERVER_INSTALLED" = "true" ] && [ "${PRESERVE_DOCS}" = false ]; then
	ds_pkg_installed_name=$(rpm -qa --qf '%{NAME}\n' | grep "${package_sysname}"-documentserver)
	if [ -n "${ds_pkg_installed_name}" ] && [ "${ds_pkg_installed_name}" != "${ds_pkg_name}" ]; then
		"${package_manager}" -y remove "${ds_pkg_installed_name}" --setopt=clean_requirements_on_remove=false
		DOCUMENT_SERVER_INSTALLED="false" RECONFIGURE_PRODUCT="true"
	elif [ "${PRODUCT_INSTALLED}" = "true" ] && config_dir_held_by_older_package; then
		# Docs 10.0.3+ declares /etc/onlyoffice as root:root, which conflicts with the owner an older Apps or DocSpace package recorded, so Docs is updated after the Apps packages replace it
		DS_UPDATE_DEFERRED="true" RECONFIGURE_PRODUCT="true"
	else
		${package_manager} -y update "${ds_pkg_installed_name}"
	fi
fi

MYSQL_SERVER_HOST=${MYSQL_SERVER_HOST:-"localhost"}
MYSQL_SERVER_DB_NAME=${MYSQL_SERVER_DB_NAME:-"${package_sysname}"}
MYSQL_SERVER_USER=${MYSQL_SERVER_USER:-"root"}
MYSQL_SERVER_PORT=${MYSQL_SERVER_PORT:-3306}
# Root-only file with the root password this installer set; it outlives the package, so a reinstall can reconnect
MYSQL_ROOT_PASS_FILE="/etc/${package_sysname}/${product}/.private/mysql-root-password"

# Probe MySQL over TCP, like the product does.
MYSQL_PROBE_HOST=$([ "${MYSQL_SERVER_HOST}" = "localhost" ] && echo "127.0.0.1" || echo "${MYSQL_SERVER_HOST}")

# Empty $1 means "try without a password".
mysql_root_connects() {
	local MYSQL_ARGS=(--connect-expired-password -h "${MYSQL_PROBE_HOST}" -P "${MYSQL_SERVER_PORT}" -u "${MYSQL_SERVER_USER}")
	# The password reaches the client through the environment, so it never appears in a command line
	if [ -n "$1" ]; then
		MYSQL_PWD="$1" mysql "${MYSQL_ARGS[@]}" -e ";" >/dev/null 2>&1
	else
		mysql "${MYSQL_ARGS[@]}" -e ";" >/dev/null 2>&1
	fi
}

# A refused password still proves the server is up.
mysql_responds() {
	local PING_OUTPUT
	PING_OUTPUT=$(mysqladmin -h "${MYSQL_PROBE_HOST}" -P "${MYSQL_SERVER_PORT}" -u "${MYSQL_SERVER_USER}" ping 2>&1) || true
	[[ "${PING_OUTPUT}" == *"alive"* || "${PING_OUTPUT}" == *"Access denied"* ]]
}

if [ "${MYSQL_FIRST_TIME_INSTALL}" = "true" ]; then
	MYSQL_TEMPORARY_ROOT_PASS=""

	if [ -f "/var/log/mysqld.log" ]; then
		MYSQL_TEMPORARY_ROOT_PASS=$(cat /var/log/mysqld.log | grep "temporary password" | rev | cut -d " " -f 1 | rev | tail -1)
	fi

	while ! mysqladmin ping -u root --silent; do
		sleep 1
	done

	if ! MYSQL_PWD="$MYSQL_TEMPORARY_ROOT_PASS" mysql "-u$MYSQL_SERVER_USER" -e ";" >/dev/null 2>&1; then
		MYSQL=(mysql --connect-expired-password -u"$MYSQL_SERVER_USER" -D mysql)
		if [ -n "$MYSQL_TEMPORARY_ROOT_PASS" ]; then
			# The temporary password stays in /var/log/mysqld.log, so root gets a new random password instead of keeping it (the fixed prefix satisfies the default password policy, and avoids ; and = that break connection strings)
			MYSQL_ROOT_PASS=${MYSQL_ROOT_PASS:-"Aa1_$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 20)"}
			# The client reads the password from the environment, so it never appears in a command line
			export MYSQL_PWD="$MYSQL_TEMPORARY_ROOT_PASS"
		fi

		MYSQL_AUTHENTICATION_PLUGIN=$("${MYSQL[@]}" -e "SHOW VARIABLES LIKE 'default_authentication_plugin';" -s | awk '{print $2}')
		MYSQL_AUTHENTICATION_PLUGIN=${MYSQL_AUTHENTICATION_PLUGIN:-caching_sha2_password}

		"${MYSQL[@]}" -e "ALTER USER '${MYSQL_SERVER_USER}'@'localhost' IDENTIFIED WITH ${MYSQL_AUTHENTICATION_PLUGIN} BY '${MYSQL_ROOT_PASS}'" >/dev/null 2>&1 || \
		"${MYSQL[@]}" -e "UPDATE user SET plugin='${MYSQL_AUTHENTICATION_PLUGIN}', authentication_string=PASSWORD('${MYSQL_ROOT_PASS}') WHERE user='${MYSQL_SERVER_USER}' and host='localhost';"
		unset MYSQL_PWD

		systemctl restart mysqld

		if [ -n "${MYSQL_ROOT_PASS}" ]; then
			install -d -m 700 -o root -g root "$(dirname "${MYSQL_ROOT_PASS_FILE}")"
			( umask 077; printf '%s\n' "${MYSQL_ROOT_PASS}" > "${MYSQL_ROOT_PASS_FILE}" )
			echo "The MySQL root password is saved in ${MYSQL_ROOT_PASS_FILE}"
		fi
	fi
elif [ "$PRODUCT_INSTALLED" = "false" ]; then
	# MySQL predates this run, so its root password was not set here.
	MYSQL_WAIT_DEADLINE=$((SECONDS + 60))
	until mysql_responds; do
		if [ "${SECONDS}" -ge "${MYSQL_WAIT_DEADLINE}" ]; then
			echo "ERROR: MySQL is already installed but does not answer on ${MYSQL_PROBE_HOST}:${MYSQL_SERVER_PORT}." >&2
			exit 1
		fi
		sleep 1
	done

	if [ -z "${MYSQL_ROOT_PASS}" ] || ! mysql_root_connects "${MYSQL_ROOT_PASS}"; then
		# Earlier installers derived this from MySQL's temporary password.
		MYSQL_RECOVERED_PASS=$(grep "temporary password" /var/log/mysqld.log 2>/dev/null | tail -1 | rev | cut -d " " -f 1 | rev | sed -e 's/;/%/g' -e 's/=/%/g')
		MYSQL_SAVED_PASS=$(head -n 1 "${MYSQL_ROOT_PASS_FILE}" 2>/dev/null)

		if [ -n "${MYSQL_SAVED_PASS}" ] && mysql_root_connects "${MYSQL_SAVED_PASS}"; then
			MYSQL_ROOT_PASS="${MYSQL_SAVED_PASS}"
		elif mysql_root_connects ""; then
			MYSQL_ROOT_PASS=""
		elif [ -n "${MYSQL_RECOVERED_PASS}" ] && mysql_root_connects "${MYSQL_RECOVERED_PASS}"; then
			MYSQL_ROOT_PASS="${MYSQL_RECOVERED_PASS}"
		else
			echo "ERROR: cannot connect to MySQL at ${MYSQL_PROBE_HOST}:${MYSQL_SERVER_PORT} as '${MYSQL_SERVER_USER}'." >&2
			echo "Pass a working password in the MYSQL_ROOT_PASS environment variable, or remove MySQL and run the installer again." >&2
			echo "Note: a '${MYSQL_SERVER_USER}' user authenticated by unix socket cannot be used, the product connects over TCP." >&2
			exit 1
		fi
	fi
fi

if [ "$DOCUMENT_SERVER_INSTALLED" = "false" ]; then
    declare -x DS_PORT=${DS_PORT:-8083}
    declare -x LISTEN_ADDRESS=127.0.0.1:${DS_PORT}
    declare -x JWT_ENABLED=${JWT_ENABLED:-true}
    declare -x JWT_SECRET=${JWT_SECRET:-$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)}
    declare -x JWT_HEADER=${JWT_HEADER:-AuthorizationJwt}
    [ -n "${WOPI_ENABLED}" ] && export WOPI_ENABLED

    [ "$INSTALLATION_TYPE" != "community" ] && setup_postgres_db

    ${package_manager} -y install ${ds_pkg_name} --nobest # --nobest for rhel 8 compatibility

	# nginx enables a default server on port 80.
	if [ -f /etc/nginx/nginx.conf ] && grep -q "server {" /etc/nginx/nginx.conf; then
		# fix Bug 81918 - Remove the default server block without dropping conf.d includes.
		[ -f /etc/nginx/nginx.conf.bak ] || cp -f /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
		echo "Note: removed default server block from /etc/nginx/nginx.conf to avoid conflict with openresty (backup: /etc/nginx/nginx.conf.bak)."
		awk '/^[[:space:]]*server[[:space:]]*\{/&&!done{done=1;d=1;next}d{d+=gsub(/\{/,"{")-gsub(/\}/,"}");if(d<=0)d=0;next}1' \
			/etc/nginx/nginx.conf > /etc/nginx/nginx.conf.tmp && mv -f /etc/nginx/nginx.conf.tmp /etc/nginx/nginx.conf
	fi

	if [ -e /etc/nginx/conf.d/default.conf ]; then
		mv -f /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled
		echo "Note: nginx default site disabled to avoid conflict with openresty."
	fi

	systemctl is-active --quiet nginx && systemctl reload nginx || systemctl start nginx

	ds_configure_args=()
	if [ "$INSTALLATION_TYPE" != "community" ]; then
		ds_configure_args=(
			--redishost "${DS_REDIS_HOST:-localhost}"
			--amqphost "${DS_RABBITMQ_HOST:-localhost}"
			--amqpuser "${DS_RABBITMQ_USER:-guest}"
			--amqppassword "${DS_RABBITMQ_PWD:-guest}"
			--databasehost "${DS_DB_HOST:-localhost}"
			--databasename "$DS_DB_NAME"
			--databaseuser "$DS_DB_USER"
			--databasepassword "$DS_DB_PWD"
		)
	fi
	documentserver-configure.sh "${ds_configure_args[@]}"
fi

if [ "$MAKESWAP" == "true" ]; then
	make_swap "/${product}_swapfile"
fi

{ ${package_manager} check-update ${package}; PRODUCT_CHECK_UPDATE=$?; } || true
if [ "$PRODUCT_INSTALLED" = "false" ]; then
	[[ ${PRODUCT_VERSION} =~ ^[0-9]+(\.[0-9]+){3}$ ]] && PRODUCT_VERSION="${PRODUCT_VERSION%.*}-${PRODUCT_VERSION##*.}"
	${package_manager} "${DOCS_RPM_OPTIONS[@]}" install -y "${package}${PRODUCT_VERSION:+-${PRODUCT_VERSION}}" --best "${APPS_ERASING_OPTIONS[@]}" $TESTING_REPO
	DB_PWD="${MYSQL_ROOT_PASS}" "${product}"-configuration -mysqlh "${MYSQL_SERVER_HOST}" -mysqlport "${MYSQL_SERVER_PORT}" -mysqld "${MYSQL_SERVER_DB_NAME}" -mysqlu "${MYSQL_SERVER_USER}"
elif ! rpm -q "${package}" >/dev/null 2>&1; then # (DS v4.0.0) take over an installation made before the rename to ONLYOFFICE Apps
	[[ ${PRODUCT_VERSION} =~ ^[0-9]+(\.[0-9]+){3}$ ]] && PRODUCT_VERSION="${PRODUCT_VERSION%.*}-${PRODUCT_VERSION##*.}"
	${package_manager} "${DOCS_RPM_OPTIONS[@]}" install -y "${package}${PRODUCT_VERSION:+-${PRODUCT_VERSION}}" --best "${APPS_ERASING_OPTIONS[@]}" $TESTING_REPO
	# With a deferred Docs update the configuration runs once, after Docs, since the Docs package resets the owner of the shared Data directory
	[ "${DS_UPDATE_DEFERRED}" = "true" ] || "${product}"-configuration
elif [[ "${PRODUCT_CHECK_UPDATE}" -eq "${UPDATE_AVAILABLE_CODE}" || "${RECONFIGURE_PRODUCT}" = "true" ]]; then
	${package_manager} "${DOCS_RPM_OPTIONS[@]}" -y update "${package}" --best "${APPS_ERASING_OPTIONS[@]}" $TESTING_REPO
	[ "${DS_UPDATE_DEFERRED}" = "true" ] || "${product}"-configuration
fi

if [ "${DS_UPDATE_DEFERRED}" = "true" ]; then
	# The Apps step may not have replaced the package that holds the directory, so the update is skipped rather than failing the whole run
	if config_dir_held_by_older_package; then
		echo "WARNING: /etc/${package_sysname} is still held by an older package, ${ds_pkg_installed_name} is not updated; update ${package} first and run the installer again" >&2
	else
		${package_manager} -y update "${ds_pkg_installed_name}"
	fi
	"${product}"-configuration
fi

echo ""
echo "$RES_INSTALL_SUCCESS"
echo "$RES_QUESTIONS"
echo ""
