#!/bin/bash

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
	"DEVELOPER") ds_pkg_name+="-de" ;;
	"ENTERPRISE") ds_pkg_name+="-ee" ;;
esac

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
fi

if [ "$DOCUMENT_SERVER_INSTALLED" = "false" ]; then
	declare -x DS_PORT=8083

	DS_RABBITMQ_HOST=localhost
	DS_RABBITMQ_USER=guest
	DS_RABBITMQ_PWD=guest
	
	DS_REDIS_HOST=localhost
	
	DS_COMMON_NAME=${DS_COMMON_NAME:-"ds"}

	DS_DB_HOST=localhost
	DS_DB_NAME=$DS_COMMON_NAME
	DS_DB_USER=$DS_COMMON_NAME
	DS_DB_PWD=$DS_COMMON_NAME
	
	declare -x JWT_ENABLED=${JWT_ENABLED:-true}
	declare -x JWT_SECRET=${JWT_SECRET:-$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)}
	declare -x JWT_HEADER=${JWT_HEADER:-AuthorizationJwt}
		
	if ! su - postgres -s /bin/bash -c "psql -lqt" | cut -d \| -f 1 | grep -q "${DS_DB_NAME}"; then
		su - postgres -s /bin/bash -c "psql -c \"CREATE USER ${DS_DB_USER} WITH password '${DS_DB_PWD}';\""
		su - postgres -s /bin/bash -c "psql -c \"CREATE DATABASE ${DS_DB_NAME} OWNER ${DS_DB_USER};\""
	fi
	
	${package_manager} -y install ${ds_pkg_name}
	
expect << EOF
	
	set timeout -1
	log_user 1
	
	spawn documentserver-configure.sh
	
	expect "Configuring database access..."
	
	expect -re "Host"
	send "$DS_DB_HOST\r"
	
	expect -re "Database name"
	send "$DS_DB_NAME\r"
	
	expect -re "User"
	send "$DS_DB_USER\r"
	
	expect -re "Password"
	send "$DS_DB_PWD\r"
	
	if { "${INSTALLATION_TYPE}" == "ENTERPRISE" || "${INSTALLATION_TYPE}" == "DEVELOPER" } {
		expect "Configuring redis access..."
		send "$DS_REDIS_HOST\r"
	}
	
	expect "Configuring AMQP access... "
	expect -re "Host"
	send "$DS_RABBITMQ_HOST\r"
	
	expect -re "User"
	send "$DS_RABBITMQ_USER\r"
	
	expect -re "Password"
	send "$DS_RABBITMQ_PWD\r"
	
	expect eof
	
EOF
fi

if [ "$MAKESWAP" == "true" ]; then
	make_swap
fi

{ ${package_manager} check-update ${product}; PRODUCT_CHECK_UPDATE=$?; } || true
if [ "$PRODUCT_INSTALLED" = "false" ]; then
	${package_manager} install -y ${product} --best --allowerasing $TESTING_REPO
	"${product}"-configuration \
		-mysqlh "${MYSQL_SERVER_HOST}" \
		-mysqlport "${MYSQL_SERVER_PORT}" \
		-mysqld "${MYSQL_SERVER_DB_NAME}" \
		-mysqlu "${MYSQL_SERVER_USER}" \
		-mysqlp "${MYSQL_ROOT_PASS}"
elif [[ "${PRODUCT_CHECK_UPDATE}" -eq "${UPDATE_AVAILABLE_CODE}" || "${RECONFIGURE_PRODUCT}" = "true" ]]; then
	${package_manager} -y update "${product}" --best --allowerasing $TESTING_REPO
	"${product}"-configuration
fi

echo ""
echo "$RES_INSTALL_SUCCESS"
echo "$RES_QUESTIONS"
echo ""
