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
		systemctl enable $SVC
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
	DS_DB_PWD=${DS_DB_PWD:-$DS_COMMON_NAME}

	if ! su - postgres -s /bin/bash -c "psql -lqt" | cut -d \| -f 1 | grep -q "${DS_DB_NAME}"; then
		su - postgres -s /bin/bash -c "psql -c \"CREATE USER ${DS_DB_USER} WITH password '${DS_DB_PWD}';\""
		su - postgres -s /bin/bash -c "psql -c \"CREATE DATABASE ${DS_DB_NAME} OWNER ${DS_DB_USER};\""
	fi
}

if [ "$UPDATE" = "true" ] && [ "$DOCUMENT_SERVER_INSTALLED" = "true" ]; then
	ds_pkg_installed_name=$(rpm -qa --qf '%{NAME}\n' | grep "${package_sysname}"-documentserver)
	if [ -n "${ds_pkg_installed_name}" ] && [ "${ds_pkg_installed_name}" != "${ds_pkg_name}" ]; then
		"${package_manager}" -y remove "${ds_pkg_installed_name}" --setopt=clean_requirements_on_remove=false
		DOCUMENT_SERVER_INSTALLED="false" RECONFIGURE_PRODUCT="true"
	else
		${package_manager} -y update "${ds_pkg_installed_name}"
	fi
fi

MYSQL_SERVER_HOST=${MYSQL_SERVER_HOST:-"localhost"}
MYSQL_SERVER_DB_NAME=${MYSQL_SERVER_DB_NAME:-"${package_sysname}"}
MYSQL_SERVER_USER=${MYSQL_SERVER_USER:-"root"}
MYSQL_SERVER_PORT=${MYSQL_SERVER_PORT:-3306}

# The product reaches MySQL over TCP, so probe the same way instead of through the local socket
MYSQL_PROBE_HOST=$([ "${MYSQL_SERVER_HOST}" = "localhost" ] && echo "127.0.0.1" || echo "${MYSQL_SERVER_HOST}")

# Empty $1 means "try connecting without a password"
mysql_root_connects() {
	local MYSQL_ARGS=(--connect-expired-password -h "${MYSQL_PROBE_HOST}" -P "${MYSQL_SERVER_PORT}" -u "${MYSQL_SERVER_USER}")
	[ -n "$1" ] && MYSQL_ARGS+=("-p$1")
	mysql "${MYSQL_ARGS[@]}" -e ";" >/dev/null 2>&1
}

# A refused password still proves the server is up, unlike a refused connection
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

	if ! mysql "-u$MYSQL_SERVER_USER" "-p$MYSQL_TEMPORARY_ROOT_PASS" -e ";" >/dev/null 2>&1; then
		if [ -z "$MYSQL_TEMPORARY_ROOT_PASS" ]; then
		   MYSQL="mysql --connect-expired-password -u$MYSQL_SERVER_USER -D mysql"
		else
		   MYSQL="mysql --connect-expired-password -u$MYSQL_SERVER_USER -p${MYSQL_TEMPORARY_ROOT_PASS} -D mysql"
		   MYSQL_ROOT_PASS=$(echo "$MYSQL_TEMPORARY_ROOT_PASS" | sed -e 's/;/%/g' -e 's/=/%/g')
		fi

		MYSQL_AUTHENTICATION_PLUGIN=$($MYSQL -e "SHOW VARIABLES LIKE 'default_authentication_plugin';" -s | awk '{print $2}')
		MYSQL_AUTHENTICATION_PLUGIN=${MYSQL_AUTHENTICATION_PLUGIN:-caching_sha2_password}

		$MYSQL -e "ALTER USER '${MYSQL_SERVER_USER}'@'localhost' IDENTIFIED WITH ${MYSQL_AUTHENTICATION_PLUGIN} BY '${MYSQL_ROOT_PASS}'" >/dev/null 2>&1 || \
		$MYSQL -e "UPDATE user SET plugin='${MYSQL_AUTHENTICATION_PLUGIN}', authentication_string=PASSWORD('${MYSQL_ROOT_PASS}') WHERE user='${MYSQL_SERVER_USER}' and host='localhost';"

		systemctl restart mysqld
	fi
elif [ "$PRODUCT_INSTALLED" = "false" ]; then
	# MySQL predates this run (an earlier failed attempt or the user's own server), so its root password was not set here
	MYSQL_WAIT_DEADLINE=$((SECONDS + 60))
	until mysql_responds; do
		if [ "${SECONDS}" -ge "${MYSQL_WAIT_DEADLINE}" ]; then
			echo "ERROR: MySQL is already installed but does not answer on ${MYSQL_PROBE_HOST}:${MYSQL_SERVER_PORT}." >&2
			exit 1
		fi
		sleep 1
	done

	if [ -z "${MYSQL_ROOT_PASS}" ] || ! mysql_root_connects "${MYSQL_ROOT_PASS}"; then
		# An earlier run of this installer derived the root password from MySQL's own temporary one
		MYSQL_RECOVERED_PASS=$(grep "temporary password" /var/log/mysqld.log 2>/dev/null | tail -1 | rev | cut -d " " -f 1 | rev | sed -e 's/;/%/g' -e 's/=/%/g')

		if mysql_root_connects ""; then
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
    [ -n "${WOPI_ENABLED}" ] && declare -x WOPI_ENABLED

    [ "$INSTALLATION_TYPE" != "community" ] && setup_postgres_db

    ${package_manager} -y install ${ds_pkg_name} --nobest # --nobest for rhel 8 compatibility

	# nginx (a dependency of ${ds_pkg_name}) enables a default server listening on port 80, which conflicts with openresty
	if [ -f /etc/nginx/nginx.conf ] && grep -q "server {" /etc/nginx/nginx.conf; then
		# fix Bug 81918 - Remove default server block without dropping conf.d includes
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
	make_swap
fi

{ ${package_manager} check-update ${package}; PRODUCT_CHECK_UPDATE=$?; } || true
if [ "$PRODUCT_INSTALLED" = "false" ]; then
	[[ ${PRODUCT_VERSION} =~ ^[0-9]+(\.[0-9]+){3}$ ]] && PRODUCT_VERSION="${PRODUCT_VERSION%.*}-${PRODUCT_VERSION##*.}"
	${package_manager} install -y "${package}${PRODUCT_VERSION:+-${PRODUCT_VERSION}}" --best --allowerasing $TESTING_REPO
	"${product}"-configuration \
		-mysqlh "${MYSQL_SERVER_HOST}" \
		-mysqlport "${MYSQL_SERVER_PORT}" \
		-mysqld "${MYSQL_SERVER_DB_NAME}" \
		-mysqlu "${MYSQL_SERVER_USER}" \
		-mysqlp "${MYSQL_ROOT_PASS}"
elif ! rpm -q "${package}" >/dev/null 2>&1; then # (DS v4.0.0) take over an installation made before the rename to ONLYOFFICE Apps
	[[ ${PRODUCT_VERSION} =~ ^[0-9]+(\.[0-9]+){3}$ ]] && PRODUCT_VERSION="${PRODUCT_VERSION%.*}-${PRODUCT_VERSION##*.}"
	${package_manager} install -y "${package}${PRODUCT_VERSION:+-${PRODUCT_VERSION}}" --best --allowerasing $TESTING_REPO
	"${product}"-configuration
elif [[ "${PRODUCT_CHECK_UPDATE}" -eq "${UPDATE_AVAILABLE_CODE}" || "${RECONFIGURE_PRODUCT}" = "true" ]]; then
	${package_manager} -y update "${package}" --best --allowerasing $TESTING_REPO
	if [[ "${RECONFIGURE_PRODUCT}" = "true" ]]; then
		ENVIRONMENT=$(grep -oP 'ENVIRONMENT=\K.*' /etc/"${package_sysname}"/"${product}"/systemd.env || grep -oP 'ENVIRONMENT=\K.*' /usr/lib/systemd/system/"${product}"-api.service)
		CONNECTION_STRING=$(json -f /etc/"${package_sysname}"/"${product}"/appsettings."$ENVIRONMENT".json ConnectionStrings.default.connectionString)
		"${product}"-configuration \
			-mysqlh "$(grep -oP 'Server=\K[^;]*' <<< "${CONNECTION_STRING}")" \
			-mysqlport "$(grep -oP 'Port=\K[^;]*' <<< "${CONNECTION_STRING}")" \
			-mysqld "$(grep -oP 'Database=\K[^;]*' <<< "${CONNECTION_STRING}")" \
			-mysqlu "$(grep -oP 'User ID=\K[^;]*' <<< "${CONNECTION_STRING}")" \
			-mysqlp "$(grep -oP 'Password=\K[^;]*' <<< "${CONNECTION_STRING}")"
	else
		"${product}"-configuration
	fi
fi

echo ""
echo "$RES_INSTALL_SUCCESS"
echo "$RES_QUESTIONS"
echo ""
