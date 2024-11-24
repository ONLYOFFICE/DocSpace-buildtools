#!/bin/bash

set -e

cat<<EOF

#######################################
#  INSTALL PREREQUISITES
#######################################

EOF

hold_package_version

if [ "$DIST" = "debian" ] && [ $(apt-cache search ttf-mscorefonts-installer | wc -l) -eq 0 ]; then
		echo "deb http://ftp.uk.debian.org/debian/ $DISTRIB_CODENAME main contrib" >> /etc/apt/sources.list
		echo "deb-src http://ftp.uk.debian.org/debian/ $DISTRIB_CODENAME main contrib" >> /etc/apt/sources.list
fi

apt-get -y update

if ! command -v locale-gen &> /dev/null; then
	apt-get install -yq locales
fi

if ! dpkg -l | grep -q "apt-transport-https"; then
	apt-get install -yq apt-transport-https
fi

if ! dpkg -l | grep -q "software-properties-common"; then
	apt-get install -yq software-properties-common
fi

locale-gen en_US.UTF-8

# add opensearch repo
curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring
echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" > /etc/apt/sources.list.d/opensearch-2.x.list
ELASTIC_VERSION="2.11.1"

#add opensearch dashboards repo
if [ ${INSTALL_FLUENT_BIT} == "true" ]; then
	curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring
	echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.x/apt stable main" > /etc/apt/sources.list.d/opensearch-dashboards-2.x.list
	DASHBOARDS_VERSION="2.11.1"
fi

#add rabbitmq & erlang repo
if [[ "${DISTRIB_CODENAME}" =~ ^(focal|bullseye)$ ]]; then
	[ ! -f /etc/apt/sources.list.d/rabbitmq.list ] && RABBITMQ_REPO=false
	curl -1sLf https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key | gpg --dearmor > /usr/share/keyrings/erlang.gpg
	curl -1sLf https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key | gpg --dearmor > /usr/share/keyrings/rabbitmq.gpg
	echo "deb [arch=amd64 signed-by=/usr/share/keyrings/erlang.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-erlang/deb/${DIST} ${DISTRIB_CODENAME} main" > /etc/apt/sources.list.d/rabbitmq.list
	echo "deb [arch=amd64 signed-by=/usr/share/keyrings/rabbitmq.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-server/deb/${DIST} ${DISTRIB_CODENAME} main" >> /etc/apt/sources.list.d/rabbitmq.list
	if dpkg -l | grep -q rabbitmq-server && [ "${RABBITMQ_REPO}" = false ]; then
		echo "You have an old version of RabbitMQ installed. The update will cause the RabbitMQ database to be deleted."
		echo "If you use the database only in the ONLYOFFICE configuration, then the update will be safe for you."
		echo "Select 'Y' to install the new version of RabbitMQ. Select 'N' to abort the installation."
		read -r -p "Please, enter Y or N: " CHOICE_INSTALLATION
		if [[ "${CHOICE_INSTALLATION,,}" =~ ^(y|yes)$ ]]; then
			apt-get purge -y rabbitmq-server $(dpkg -l | awk '/erlang/ {print $2}')
		else
			rm -f /etc/apt/sources.list.d/rabbitmq.list
			exit 1
		fi
	fi
fi

# add nodejs repo
NODE_VERSION="18"
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -

#add dotnet repo
if [ "$DIST" = "debian" ] || [ "$DISTRIB_CODENAME" = "focal" ]; then
	curl https://packages.microsoft.com/config/$DIST/$REV/packages-microsoft-prod.deb -O
	echo -e "Package: *\nPin: origin \"packages.microsoft.com\"\nPin-Priority: 1002" | tee /etc/apt/preferences.d/99microsoft-prod.pref
	dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb
elif dpkg -l | grep -q packages-microsoft-prod; then
    apt-get purge -y packages-microsoft-prod
fi

MYSQL_REPO_VERSION="$(curl https://repo.mysql.com | grep -oP 'mysql-apt-config_\K.*' | grep -o '^[^_]*' | sort --version-sort --field-separator=. | tail -n1)"
MYSQL_PACKAGE_NAME="mysql-apt-config_${MYSQL_REPO_VERSION}_all.deb"
if ! dpkg -l | grep -q "mysql-server"; then

	MYSQL_SERVER_HOST=${MYSQL_SERVER_HOST:-"localhost"}
	MYSQL_SERVER_DB_NAME=${MYSQL_SERVER_DB_NAME:-"${package_sysname}"}
	MYSQL_SERVER_USER=${MYSQL_SERVER_USER:-"root"}
	MYSQL_SERVER_PASS=${MYSQL_SERVER_PASS:-"$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"}

	# setup mysql 8.4 package
	curl -OL http://repo.mysql.com/${MYSQL_PACKAGE_NAME}
	echo "mysql-apt-config mysql-apt-config/repo-codename  select  $DISTRIB_CODENAME" | debconf-set-selections
	echo "mysql-apt-config mysql-apt-config/repo-distro  select  $DIST" | debconf-set-selections
	echo "mysql-apt-config mysql-apt-config/select-server  select  mysql-8.4-lts" | debconf-set-selections
	DEBIAN_FRONTEND=noninteractive dpkg -i ${MYSQL_PACKAGE_NAME}
	rm -f ${MYSQL_PACKAGE_NAME}

	echo mysql-community-server mysql-community-server/root-pass password ${MYSQL_SERVER_PASS} | debconf-set-selections
	echo mysql-community-server mysql-community-server/re-root-pass password ${MYSQL_SERVER_PASS} | debconf-set-selections
	echo mysql-community-server mysql-server/default-auth-override select "Use Strong Password Encryption (RECOMMENDED)" | debconf-set-selections
	echo mysql-server mysql-server/root_password password ${MYSQL_SERVER_PASS} | debconf-set-selections
	echo mysql-server mysql-server/root_password_again password ${MYSQL_SERVER_PASS} | debconf-set-selections

elif dpkg -l | grep -q "mysql-apt-config" && [ "$(apt-cache policy mysql-apt-config | awk 'NR==2{print $2}')" != "${MYSQL_REPO_VERSION}" ]; then
	curl -OL http://repo.mysql.com/${MYSQL_PACKAGE_NAME}
	DEBIAN_FRONTEND=noninteractive dpkg -i ${MYSQL_PACKAGE_NAME}
	rm -f ${MYSQL_PACKAGE_NAME}
fi

# add redis repo  --- temporary fix for complete installation on Ubuntu 24.04. REDIS_DIST_CODENAME change to DISTRIB_CODENAME
if [ "$DIST" = "ubuntu" ]; then	
	[[ "$DISTRIB_CODENAME" =~ noble ]] && REDIS_DIST_CODENAME="jammy" || REDIS_DIST_CODENAME="${DISTRIB_CODENAME}"
	curl -fsSL https://packages.redis.io/gpg | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/redis.gpg --import
	echo "deb [signed-by=/usr/share/keyrings/redis.gpg] https://packages.redis.io/deb $REDIS_DIST_CODENAME main" | tee /etc/apt/sources.list.d/redis.list
	chmod 644 /usr/share/keyrings/redis.gpg
fi

#add nginx repo
if [[ "$DISTRIB_CODENAME" != noble ]]; then
	curl -s http://nginx.org/keys/nginx_signing.key | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/nginx.gpg --import
	echo "deb [signed-by=/usr/share/keyrings/nginx.gpg] http://nginx.org/packages/$DIST/ $DISTRIB_CODENAME nginx" | tee /etc/apt/sources.list.d/nginx.list
	chmod 644 /usr/share/keyrings/nginx.gpg
fi
# Fix for missing nginx repository for debian bookworm
[ "$DISTRIB_CODENAME" = "bookworm" ] && sed -i "s/$DISTRIB_CODENAME/buster/g" /etc/apt/sources.list.d/nginx.list

#add openresty repo --- temporary fix for complete installation on Ubuntu 24.04: OPENRESTY_DIST_CODENAME change to DISTRIB_CODENAME
[[ "$DISTRIB_CODENAME" =~ noble ]] && OPENRESTY_DIST_CODENAME="jammy" || OPENRESTY_DIST_CODENAME="${DISTRIB_CODENAME}"
curl -fsSL https://openresty.org/package/pubkey.gpg | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/openresty.gpg --import
echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/$DIST $OPENRESTY_DIST_CODENAME $([ "$DIST" = "ubuntu" ] && echo "main" || echo "openresty" )" | tee /etc/apt/sources.list.d/openresty.list
chmod 644 /usr/share/keyrings/openresty.gpg

#add java repo
curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /usr/share/keyrings/adoptium.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $DISTRIB_CODENAME main" | tee /etc/apt/sources.list.d/adoptium.list
chmod 644 /usr/share/keyrings/adoptium.gpg
JAVA_VERSION="21"

# setup msttcorefonts
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections

# install
apt-get -y update
apt-get install -o DPkg::options::="--force-confnew" -yq \
				expect \
				nano \
				nodejs \
				gcc \
				make \
				dotnet-sdk-8.0 \
				mysql-server \
				mysql-client \
				postgresql \
				redis-server \
				rabbitmq-server \
				temurin-${JAVA_VERSION}-jre \
				ffmpeg 

if ! dpkg -l | grep -q "opensearch"; then
	apt-get install -yq opensearch=${ELASTIC_VERSION}
fi
# Set Java ${JAVA_VERSION} as the default version
JAVA_PATH=$(find /usr/lib/jvm/ -name "java" -path "*temurin-${JAVA_VERSION}*" | head -1)
update-alternatives --install /usr/bin/java java "$JAVA_PATH" 100 && update-alternatives --set java "$JAVA_PATH"

if [ ${INSTALL_FLUENT_BIT} == "true" ]; then
	[[ "$DISTRIB_CODENAME" =~ noble ]] && FLUENTBIT_DIST_CODENAME="jammy" || FLUENTBIT_DIST_CODENAME="${DISTRIB_CODENAME}"
	curl https://packages.fluentbit.io/fluentbit.key | gpg --dearmor > /usr/share/keyrings/fluentbit-keyring.gpg
	echo "deb [signed-by=/usr/share/keyrings/fluentbit-keyring.gpg] https://packages.fluentbit.io/$DIST/$FLUENTBIT_DIST_CODENAME $FLUENTBIT_DIST_CODENAME main" | tee /etc/apt/sources.list.d/fluent-bit.list
	apt update
	apt-get install -yq opensearch-dashboards=${DASHBOARDS_VERSION} fluent-bit
fi

# disable apparmor for mysql
if which apparmor_parser && [ ! -f /etc/apparmor.d/disable/usr.sbin.mysqld ] && [ -f /etc/apparmor.d/disable/usr.sbin.mysqld ]; then
	ln -sf /etc/apparmor.d/usr.sbin.mysqld /etc/apparmor.d/disable/;
	apparmor_parser -R /etc/apparmor.d/usr.sbin.mysqld;
fi
