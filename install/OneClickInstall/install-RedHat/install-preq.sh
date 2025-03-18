#!/bin/bash

set -e

cat<<EOF

#######################################
#  INSTALL PREREQUISITES
#######################################

EOF

# clean yum cache
${package_manager} clean all

${package_manager} -y install yum-utils

{ yum check-update postgresql; PSQLExitCode=$?; } || true #Checking for postgresql update
{ yum check-update "$DIST"*-release; exitCode=$?; } || true #Checking for distribution update

if rpm -qa | grep 'mariadb.*config' >/dev/null 2>&1; then
   echo "$RES_MARIADB" && exit 0
fi

#Add repository EPEL
EPEL_URL="https://dl.fedoraproject.org/pub/epel/"
[ "$DIST" != "fedora" ] && { rpm -ivh ${EPEL_URL}/epel-release-latest-$REV.noarch.rpm || true; }
[ "$REV" = "9" ] && update-crypto-policies --set DEFAULT:SHA1 && ${package_manager} -y install xorg-x11-font-utils
[ "$DIST" = "centos" ] && TESTING_REPO="--enablerepo=$( [ "$REV" = "9" ] && echo "crb" || echo "powertools" )"
if [ "$DIST" = "redhat" ]; then 
	LADSPA_PACKAGE_VERSION=$(curl -s "${EPEL_URL}/10/Everything/x86_64/Packages/l/" | grep -oP 'ladspa-[0-9].*?\.rpm' | sort -V | tail -n 1)
	${package_manager} install -y "${EPEL_URL}/10/Everything/x86_64/Packages/l/${LADSPA_PACKAGE_VERSION}"
fi

#add rabbitmq & erlang repo
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | bash

#add nodejs repo
NODE_VERSION="18"
curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | sed '/update -y/d' | bash - || true

#add mysql repo
dnf remove -y @mysql && dnf module -y reset mysql && dnf module -y disable mysql
MYSQL_REPO_VERSION="$(curl https://repo.mysql.com | grep -oP "mysql84-community-release-${MYSQL_DISTR_NAME}${REV}-\K.*" | grep -o '^[^.]*' | sort | tail -n1)"
yum install -y https://repo.mysql.com/mysql84-community-release-"${MYSQL_DISTR_NAME}""${REV}"-"${MYSQL_REPO_VERSION}".noarch.rpm || true

if ! rpm -q mysql-community-server; then
	MYSQL_FIRST_TIME_INSTALL="true"
fi

#add opensearch repo
curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.x.repo -o /etc/yum.repos.d/opensearch-2.x.repo
ELASTIC_VERSION="2.18.0"
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="$(echo "${package_sysname}!A1")"

#add opensearch dashboards repo
if [ ${INSTALL_FLUENT_BIT} == "true" ]; then
	curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.x/opensearch-dashboards-2.x.repo -o /etc/yum.repos.d/opensearch-dashboards-2.x.repo
	DASHBOARDS_VERSION="2.18.0"
fi

# add nginx repo, Fedora doesn't need it
if [ "$DIST" != "fedora" ]; then
cat > /etc/yum.repos.d/nginx.repo <<END
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/$REV/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
END
fi

rpm --import https://openresty.org/package/pubkey.gpg
OPENRESTY_REPO_FILE=$( [[ "$REV" -ge 9 && "$DIST" != "fedora" ]] && echo "openresty2.repo" || echo "openresty.repo" )
curl -o /etc/yum.repos.d/openresty.repo "https://openresty.org/package/${OPENRESTY_DISTR_NAME}/${OPENRESTY_REPO_FILE}"
[ "$DIST" == "fedora" ] && sed -i "s/\$releasever/$OPENRESTY_REV/g" /etc/yum.repos.d/openresty.repo

JAVA_VERSION=21
${package_manager} -y install $([ "$DIST" != "fedora" ] && echo "epel-release") \
			python3 \
			nodejs ${NODEJS_OPTION} \
			dotnet-sdk-9.0 \
			opensearch-${ELASTIC_VERSION} \
			mysql-community-server \
			postgresql \
			postgresql-server \
			rabbitmq-server$rabbitmq_version \
			redis \
			SDL2 \
			expect \
			java-${JAVA_VERSION}-openjdk-headless \
			--enablerepo=opensearch-2.x

# Set Java ${JAVA_VERSION} as the default version
JAVA_PATH=$(find /usr/lib/jvm/ -name "java" -path "*java-${JAVA_VERSION}*" | head -1)
alternatives --install /usr/bin/java java "$JAVA_PATH" 100 && alternatives --set java "$JAVA_PATH"

#add repo, install fluent-bit
if [ "${INSTALL_FLUENT_BIT}" == "true" ]; then 
	[ "$DIST" != "fedora" ] && curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | bash || yum -y install fluent-bit
	${package_manager} -y install opensearch-dashboards-"${DASHBOARDS_VERSION}" --enablerepo=opensearch-dashboards-2.x
fi

if [[ $PSQLExitCode -eq $UPDATE_AVAILABLE_CODE ]]; then
	yum -y install postgresql-upgrade
	postgresql-setup --upgrade || true
fi
postgresql-setup --initdb || true

sed -E -i "s/(host\s+(all|replication)\s+all\s+(127\.0\.0\.1\/32|\:\:1\/128)\s+)(ident|trust|md5)/\1scram-sha-256/" /var/lib/pgsql/data/pg_hba.conf
sed -i "s/^#\?password_encryption = .*/password_encryption = 'scram-sha-256'/" /var/lib/pgsql/data/postgresql.conf

if ! command -v semanage &> /dev/null; then
	yum install -y policycoreutils-python || yum install -y policycoreutils-python-utils
fi 

semanage permissive -a httpd_t

package_services="rabbitmq-server postgresql redis mysqld"
rpm -q valkey &>/dev/null && package_services="${package_services//redis/valkey}" || true # https://fedoraproject.org/wiki/Changes/Replace_Redis_With_Valkey 
