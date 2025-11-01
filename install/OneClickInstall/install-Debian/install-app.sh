#!/bin/bash

set -e

cat<<EOF

#######################################
#  INSTALL APP
#######################################

EOF
apt-get -y update

ds_pkg_name="${package_sysname}-documentserver"
case "${INSTALLATION_TYPE}" in
	"DEVELOPER") ds_pkg_name+="-de" ;;
	"ENTERPRISE") ds_pkg_name+="-ee" ;;
esac

if [ "$UPDATE" = "true" ] && [ "$DOCUMENT_SERVER_INSTALLED" = "true" ]; then
	ds_pkg_installed_name=$(dpkg -l | grep "${package_sysname}"-documentserver | tail -n1 | awk '{print $2}')
	if [ -n "${ds_pkg_installed_name}" ] && [ "${ds_pkg_installed_name}" != "${ds_pkg_name}" ]; then
		debconf-get-selections | grep ^"${ds_pkg_installed_name}" | sed s/"${ds_pkg_installed_name}"/"${ds_pkg_name}"/g | debconf-set-selections
		DEBIAN_FRONTEND=noninteractive apt-get purge -yq "${ds_pkg_installed_name}"
		apt-get install -yq "${ds_pkg_name}"
		RECONFIGURE_PRODUCT="true"
	else
		apt-get install -y --only-upgrade "${ds_pkg_name}"
	fi
fi

if [ "$DOCUMENT_SERVER_INSTALLED" = "false" ]; then
	DS_PORT=${DS_PORT:-8083}

	DS_DB_HOST=localhost
	DS_DB_NAME=$DS_COMMON_NAME
	DS_DB_USER=$DS_COMMON_NAME
	DS_DB_PWD=$DS_COMMON_NAME
	
	DS_JWT_ENABLED=${DS_JWT_ENABLED:-true}
	DS_JWT_SECRET=${DS_JWT_SECRET:-$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)}
	DS_JWT_HEADER=${DS_JWT_HEADER:-AuthorizationJwt}

	if ! su - postgres -s /bin/bash -c "psql -lqt" | cut -d \| -f 1 | grep -q "${DS_DB_NAME}"; then
		su - postgres -s /bin/bash -c "psql -c \"CREATE USER ${DS_DB_USER} WITH password '${DS_DB_PWD}';\""
		su - postgres -s /bin/bash -c "psql -c \"CREATE DATABASE ${DS_DB_NAME} OWNER ${DS_DB_USER};\""
	fi

	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/ds-port select "$DS_PORT" | debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/db-pwd select "$DS_DB_PWD" | debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/db-user select "$DS_DB_USER" | debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/db-name select "$DS_DB_NAME" | debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/jwt-enabled select "${DS_JWT_ENABLED}" | debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/jwt-secret select "${DS_JWT_SECRET}" | debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/jwt-header select "${DS_JWT_HEADER}" | debconf-set-selections
	
	apt-get install -yq "${ds_pkg_name}"
fi

if [ "$MAKESWAP" == "true" ]; then
	make_swap
fi

if [ "$PRODUCT_INSTALLED" = "false" ]; then
	echo "${product}" "${product}"/db-host select "$MYSQL_SERVER_HOST" | debconf-set-selections
	echo "${product}" "${product}"/db-port select "$MYSQL_SERVER_PORT" | debconf-set-selections
	echo "${product}" "${product}"/db-name select "$MYSQL_SERVER_DB_NAME" | debconf-set-selections
	echo "${product}" "${product}"/db-user select "$MYSQL_SERVER_USER" | debconf-set-selections
	echo "${product}" "${product}"/db-pwd select "$MYSQL_SERVER_PASS" | debconf-set-selections

	if apt-get install -y "${product}"; then
		# Clear the password in debconf for a successful update when using external MySQL
		if [ "$(echo "GET ${PRODUCT}/db-pwd" | debconf-communicate "$PRODUCT" | awk '{print $2}')" = "$MYSQL_SERVER_PASS" ]; then
			printf "SET ${product}/db-host\nSET ${product}/db-name\nSET ${product}/db-user\nSET ${product}/db-pwd\nSET ${product}/db-port\n" | debconf-communicate ${product} >/dev/null
		fi
	else
		echo "Error: installation of ${product} failed."
		exit 1
	fi
elif [ "$UPDATE" = "true" ] && [ "$PRODUCT_INSTALLED" = "true" ]; then
	CURRENT_VERSION=$(dpkg-query -W -f='${Version}' "${product}" 2>/dev/null)
	AVAILABLE_VERSIONS=$(apt show "${product}" 2>/dev/null | grep -E '^Version:' | awk '{print $2}')
	if [[ "$AVAILABLE_VERSIONS" != *"$CURRENT_VERSION"* ]]; then
		apt-get install -o DPkg::options::="--force-confnew" -y --only-upgrade "${product}" opensearch="${ELASTIC_VERSION}"
	elif [ "${RECONFIGURE_PRODUCT}" = "true" ]; then
		DEBIAN_FRONTEND=noninteractive dpkg-reconfigure "${product}"
	fi
fi

echo ""
echo "$RES_INSTALL_SUCCESS"
echo "$RES_QUESTIONS"
echo ""
