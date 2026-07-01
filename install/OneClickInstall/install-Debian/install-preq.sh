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
#  INSTALL PREREQUISITES
#######################################

EOF

hold_package_version

if [ "$DIST" = "debian" ] && [ "$(apt-cache search ttf-mscorefonts-installer | wc -l)" -eq 0 ]; then
		echo "deb http://deb.debian.org/debian/ $DISTRIB_CODENAME main contrib" >> /etc/apt/sources.list
fi

# Temporary workaround extend apt-sequoia policy until 2027-02-01 (OpenResty/OpenSearch)
if [ "$DISTRIB_CODENAME" = "trixie" ]; then
    install -D /usr/share/apt/default-sequoia.config /etc/crypto-policies/back-ends/apt-sequoia.config
    sed -i 's/2026-02-01/2027-02-01/' /etc/crypto-policies/back-ends/apt-sequoia.config
fi

apt-get -y update

if [ -n "$PRODUCT_VERSION" ] && ! apt-cache madison "$product" | awk '{print $3}' | grep -Eq "^${PRODUCT_VERSION}([.-]|$)"; then
  echo "Requested ${product_name} version ${PRODUCT_VERSION} not found in repository."; exit 1
fi

dpkg -l | grep -q "debconf-utils" || apt-get install -yq debconf-utils
command -v locale-gen &>/dev/null || apt-get install -yq locales
locale-gen en_US.UTF-8

# add opensearch repo
curl -fsSL https://artifacts.opensearch.org/publickeys/opensearch-release.pgp | gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring
echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/3.x/apt stable main" > /etc/apt/sources.list.d/opensearch-3.x.list
ELASTIC_VERSION="3.5.0"
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="$(echo "${package_sysname}!A1")"

#add opensearch dashboards repo
if [ "${INSTALL_FLUENT_BIT}" == "true" ]; then
	curl -fsSL https://artifacts.opensearch.org/publickeys/opensearch-release.pgp | gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring
	echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/3.x/apt stable main" > /etc/apt/sources.list.d/opensearch-dashboards-3.x.list
	DASHBOARDS_VERSION="3.5.0"
fi

# add nodejs repo
NODE_VERSION="22"
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -

#add dotnet repo
if [ "$DIST" = "ubuntu" ]; then
    add-apt-repository -y ppa:dotnet/backports
elif [ "$DIST" = "debian" ]; then
	curl -fsSL https://packages.microsoft.com/config/"$DIST"/"$REV"/packages-microsoft-prod.deb -O
	echo -e "Package: *\nPin: origin \"packages.microsoft.com\"\nPin-Priority: 1002" | tee /etc/apt/preferences.d/99microsoft-prod.pref
	DEBIAN_FRONTEND=noninteractive dpkg --force-confnew -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb
fi

MYSQL_REPO_VERSION="$(curl -fsSL https://dev.mysql.com/downloads/repo/apt/ | grep -oP '(?<=mysql-apt-config_)[0-9.]+-[0-9]+(?=_all\.deb)' | head -n1)"
MYSQL_PACKAGE_NAME="mysql-apt-config_${MYSQL_REPO_VERSION}_all.deb"
if ! dpkg -l | grep -q "mysql-server"; then

	MYSQL_SERVER_HOST=${MYSQL_SERVER_HOST:-"localhost"}
	MYSQL_SERVER_PORT=${MYSQL_SERVER_PORT:-"3306"}
	MYSQL_SERVER_DB_NAME=${MYSQL_SERVER_DB_NAME:-"${package_sysname}"}
	MYSQL_SERVER_USER=${MYSQL_SERVER_USER:-"root"}
	MYSQL_SERVER_PASS=${MYSQL_SERVER_PASS:-"$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"}

	# setup mysql 8.4 package
	curl -fsSLO http://repo.mysql.com/"${MYSQL_PACKAGE_NAME}"
	echo "mysql-apt-config mysql-apt-config/repo-codename  select  ${DISTRIB_CODENAME/resolute/noble}" | debconf-set-selections
	echo "mysql-apt-config mysql-apt-config/repo-distro  select  $DIST" | debconf-set-selections
	echo "mysql-apt-config mysql-apt-config/select-server  select  mysql-8.4-lts" | debconf-set-selections
	DEBIAN_FRONTEND=noninteractive dpkg -i "${MYSQL_PACKAGE_NAME}"
	rm -f "${MYSQL_PACKAGE_NAME}"

	echo mysql-community-server mysql-community-server/root-pass password "${MYSQL_SERVER_PASS}" | debconf-set-selections
	echo mysql-community-server mysql-community-server/re-root-pass password "${MYSQL_SERVER_PASS}" | debconf-set-selections
	echo mysql-community-server mysql-server/default-auth-override select "Use Strong Password Encryption (RECOMMENDED)" | debconf-set-selections
	echo mysql-server mysql-server/root_password password "${MYSQL_SERVER_PASS}" | debconf-set-selections
	echo mysql-server mysql-server/root_password_again password "${MYSQL_SERVER_PASS}" | debconf-set-selections

elif dpkg -l | grep -q "mysql-apt-config" && [ "$(apt-cache policy mysql-apt-config | awk 'NR==2{print $2}')" != "${MYSQL_REPO_VERSION}" ]; then
	curl -fsSLO http://repo.mysql.com/${MYSQL_PACKAGE_NAME}
	DEBIAN_FRONTEND=noninteractive dpkg -i "${MYSQL_PACKAGE_NAME}"
	rm -f "${MYSQL_PACKAGE_NAME}"
fi

if [ "$DIST" = "ubuntu" ]; then	
	curl -fsSL https://packages.redis.io/gpg | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/redis.gpg --import
	echo "deb [signed-by=/usr/share/keyrings/redis.gpg] https://packages.redis.io/deb ${DISTRIB_CODENAME} main" | tee /etc/apt/sources.list.d/redis.list
	chmod 644 /usr/share/keyrings/redis.gpg
fi

curl -fsSL https://openresty.org/package/pubkey.gpg | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/openresty.gpg --import
# Temporary workaround Debian 13 (trixie) and Ubuntu 26.04 (resolute) use previous LTS codename for OpenResty
OPENRESTY_CODENAME=$([ "${DISTRIB_CODENAME}" = "trixie" ] && echo "bookworm" || echo "${DISTRIB_CODENAME/resolute/noble}")
echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/$DIST ${OPENRESTY_CODENAME} $([ "$DIST" = "ubuntu" ] && echo "main" || echo "openresty" )" | tee /etc/apt/sources.list.d/openresty.list
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
				mysql-server \
				mysql-client \
				redis-server \
				rabbitmq-server \
				temurin-${JAVA_VERSION}-jre \
				ffmpeg 

if [ "$INSTALLATION_TYPE" != "COMMUNITY" ]; then
	apt-get install -yq postgresql
fi

# Temporary fallback dotnet-sdk-10.0 on Debian 11 and Ubuntu 24.04
DOTNET_VERSION="10.0.100"; DOTNET_PKG="dotnet-sdk-${DOTNET_VERSION%.*}"
if ! apt-get install -yq "${DOTNET_PKG}"; then
  curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --version "${DOTNET_VERSION}" --install-dir /usr/share/dotnet
  ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet

  DOTNET_PKGDIR="/tmp/${DOTNET_PKG}"; mkdir -p "${DOTNET_PKGDIR}/DEBIAN"
  printf "Package: %s\nVersion: %s\nArchitecture: amd64\nMaintainer: local\nDescription: Provides .NET %s SDK\n" \
	"${DOTNET_PKG}" "${DOTNET_VERSION}" "${DOTNET_VERSION%%.*}" > "${DOTNET_PKGDIR}/DEBIAN/control"

  dpkg-deb --build "${DOTNET_PKGDIR}" "/tmp/${DOTNET_PKG}.deb" && dpkg -i "/tmp/${DOTNET_PKG}.deb"
  rm -rf "${DOTNET_PKGDIR}" "/tmp/${DOTNET_PKG}.deb"
fi

if ! dpkg -l | grep -q "opensearch"; then
	apt-get install -yq opensearch=${ELASTIC_VERSION}
else
	ELASTIC_PLUGIN="/usr/share/opensearch/bin/opensearch-plugin"
	if dpkg --compare-versions "$(dpkg-query -W -f='${Version}\n' opensearch 2>/dev/null || true)" ne "$ELASTIC_VERSION"; then
		"${ELASTIC_PLUGIN}" list | grep -q ingest-attachment && "${ELASTIC_PLUGIN}" remove -s ingest-attachment
		systemctl restart opensearch || true
	fi
fi

# Set Java ${JAVA_VERSION} as the default version
JAVA_PATH=$(find /usr/lib/jvm/ -name "java" -path "*temurin-${JAVA_VERSION}*" | head -1)
update-alternatives --install /usr/bin/java java "$JAVA_PATH" 100 && update-alternatives --set java "$JAVA_PATH"

if [ "${INSTALL_FLUENT_BIT}" == "true" ]; then
	curl -fsSL https://packages.fluentbit.io/fluentbit.key | gpg --dearmor > /usr/share/keyrings/fluentbit-keyring.gpg
	echo "deb [signed-by=/usr/share/keyrings/fluentbit-keyring.gpg] https://packages.fluentbit.io/$DIST/$DISTRIB_CODENAME $DISTRIB_CODENAME main" | tee /etc/apt/sources.list.d/fluent-bit.list
	apt-get -y update
	apt-get install -o DPkg::options::="--force-confnew" -yq opensearch-dashboards="${DASHBOARDS_VERSION}" fluent-bit
fi

