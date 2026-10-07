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

run_remote_bash() {
	local URL="$1"
	shift
	local SCRIPT_TMP

	SCRIPT_TMP="$(mktemp)"
	curl -fsSL --retry 3 --retry-delay 2 "${URL}" -o "${SCRIPT_TMP}" || { rm -f "${SCRIPT_TMP}"; return 1; }
	bash -n "${SCRIPT_TMP}" || { rm -f "${SCRIPT_TMP}"; return 1; }
	bash "${SCRIPT_TMP}" "$@"
	local EXIT_CODE=$?
	rm -f "${SCRIPT_TMP}"
	return "${EXIT_CODE}"
}

# Clean yum cache.
${package_manager} clean all

${package_manager} -y install yum-utils

if [ -n "$PRODUCT_VERSION" ] && ! ${package_manager} --showduplicates list "$package" | awk '{print $2}' | grep -Eq "^${PRODUCT_VERSION}([.-]|$)"; then
  echo "Requested ${product_name} version ${PRODUCT_VERSION} not found in repository."; exit 1
fi

if rpm -qa | grep 'mariadb.*config' | grep -v 'connector' >/dev/null 2>&1; then
   echo "$RES_MARIADB" && exit 0
fi

# Add EPEL repo.
EPEL_URL="https://dl.fedoraproject.org/pub/epel/"
[ "$DIST" != "fedora" ] && { rpm -ivh ${EPEL_URL}/epel-release-latest-$REV.noarch.rpm || true; }
[ "$REV" = "9" ] && update-crypto-policies --set DEFAULT:SHA1
[ "$DIST" = "centos" ] && TESTING_REPO="--enablerepo=$( [ "$REV" -ge "9" ] && echo "crb" || echo "powertools" )"
if [ "$DIST" = "redhat" ] && [ "$REV" -ge 9 ]; then 
	LADSPA_PACKAGE_VERSION=$(curl -fsSL "${EPEL_URL}/10/Everything/${ARCH}/Packages/l/" | grep -oP 'ladspa-[0-9].*?\.rpm' | sort -V | tail -n 1)
	[ -n "${LADSPA_PACKAGE_VERSION}" ] || { echo "ERROR: ladspa package not found for ${ARCH}" >&2; exit 1; }
	${package_manager} install -y "${EPEL_URL}/10/Everything/${ARCH}/Packages/l/${LADSPA_PACKAGE_VERSION}"
fi

# Add RabbitMQ and Erlang repos.
if [ "$DIST" != "fedora" ]; then
	os=${RABBIT_DIST_NAME} dist="${RABBIT_DIST_VER}" run_remote_bash "https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh"
	if [ "$ARCH" = "aarch64" ]; then
		ERLANG_MAJOR=$(dnf repoquery -q --requires --latest-limit=1 rabbitmq-server | awk '/^erlang >= / {split($3,v,"."); print v[1]; exit}')
		ERLANG_RPM_URL=$(curl -fsSL "https://api.github.com/repos/rabbitmq/erlang-rpm/releases?per_page=100" | grep -oP "https://github.com/rabbitmq/erlang-rpm/releases/download/v${ERLANG_MAJOR}[^\"]*/erlang-[0-9][^\"]*-1.el${REV}.${ARCH}.rpm" | head -n 1)
		[ -n "${ERLANG_RPM_URL}" ] || { echo "ERROR: erlang package not found for ${ARCH}" >&2; exit 1; }
		${package_manager} -y install "${ERLANG_RPM_URL}"
	else
		os="${ERLANG_DIST_NAME}" dist="${ERLANG_DIST_VER}" run_remote_bash "https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh"
	fi
fi

# Add Node.js repo.
NODE_VERSION="24"
run_remote_bash "https://rpm.nodesource.com/setup_${NODE_VERSION}.x"

# Distro modularity exists only on EL8/EL9; on EL10 and Fedora there are no modules.
if [ "$DIST" != "fedora" ] && [ "$REV" -lt 10 ]; then
	dnf remove -y @mysql; dnf module -y reset mysql; dnf module -y disable mysql
fi

# Add MySQL repo.
MYSQL_LTS_MAJOR="8.4"
MYSQL_LTS_REPO="mysql-${MYSQL_LTS_MAJOR}-lts-community"
MYSQL_REPO_VERSION="$(curl -fsSL https://repo.mysql.com | grep -oP "mysql84-community-release-${MYSQL_DISTR_NAME}${MYSQL_REPO_REV}-\K.*" | grep -o '^[^.]*' | sort -n | tail -n1)"
yum install -y https://repo.mysql.com/mysql84-community-release-"${MYSQL_DISTR_NAME}""${MYSQL_REPO_REV}"-"${MYSQL_REPO_VERSION}".noarch.rpm || true
yum-config-manager --disable 'mysql*' >/dev/null 2>&1 || true
yum-config-manager --enable "${MYSQL_LTS_REPO}" >/dev/null 2>&1 || { echo "ERROR: failed to enable ${MYSQL_LTS_REPO} repo" >&2; exit 1; }
[ "$DIST" = "fedora" ] && sed -i "s/\$releasever/${MYSQL_REPO_REV}/g" /etc/yum.repos.d/mysql-community*.repo
{ [ "$DIST" = "fedora" ] || [ "$REV" -ge 10 ]; } && WEAK_OPT="--setopt=install_weak_deps=False"
MYSQL_CANDIDATE="$(dnf repoquery -q --available --repo="${MYSQL_LTS_REPO}" --queryformat='%{version}\n' mysql-community-server 2>/dev/null | grep -E '^[0-9]' | sort -V | tail -n1)"
[[ -n "${MYSQL_CANDIDATE}" && "${MYSQL_CANDIDATE}" == ${MYSQL_LTS_MAJOR}.* ]] || { echo "ERROR: mysql-community-server ${MYSQL_LTS_MAJOR}.x not available for ${DIST}${REV}, found: '${MYSQL_CANDIDATE}'" >&2; exit 1; }
rpm -q mysql-community-server >/dev/null 2>&1 || MYSQL_FIRST_TIME_INSTALL="true"

# Add OpenSearch repo.
curl -fsSL https://artifacts.opensearch.org/releases/bundle/opensearch/3.x/opensearch-3.x.repo -o /etc/yum.repos.d/opensearch-3.x.repo
OPENSEARCH_VERSION="3.5.0"
export OPENSEARCH_INITIAL_ADMIN_PASSWORD="$(echo "${package_sysname}!A1")"

# Add OpenSearch Dashboards repo.
if [ ${INSTALL_FLUENT_BIT} == "true" ]; then
	curl -fsSL https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/3.x/opensearch-dashboards-3.x.repo -o /etc/yum.repos.d/opensearch-dashboards-3.x.repo
	DASHBOARDS_VERSION="3.5.0"
fi

# Add nginx repo; Fedora doesn't need it.
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

OPENRESTY_REPO_FILE=$( [[ "$REV" -ge 9 && "$DIST" != "fedora" ]] && echo "openresty2.repo" || echo "openresty.repo" )
curl -fsSL -o /etc/yum.repos.d/openresty.repo "https://openresty.org/package/${OPENRESTY_DISTR_NAME}/${OPENRESTY_REPO_FILE}"
[ -n "${OPENRESTY_REV}" ] && sed -i "s/\$releasever/$OPENRESTY_REV/g" /etc/yum.repos.d/openresty.repo
# Temporarily disable GPG checks; OpenResty key may fail on CentOS 10.
[ "$DIST" = "centos" ] && [ "$REV" -ge 10 ] && sed -i 's/^gpgcheck=.*/gpgcheck=0/' /etc/yum.repos.d/openresty.repo

if [ "${DIST}" = "redhat" ] && [ "${REV}" = "8" ]; then
  CRB_REPO=$(dnf -q repolist all | awk "/^codeready-builder-for-rhel-8-${ARCH}-rpms/ {print \$1; exit} /^codeready-builder-for-rhel-8-rhui-rpms/ {print \$1; exit}")
  [ -n "${CRB_REPO}" ] && subscription-manager repos --enable="${CRB_REPO}" || true
  CRB_REPO=${CRB_REPO:+--enablerepo=${CRB_REPO}}
  ${package_manager} -y install https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${REV}.noarch.rpm
fi

if [ "$DIST" = "fedora" ] && [ "$REV" -ge 44 ]; then
cat > /etc/yum.repos.d/adoptium.repo <<END
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/fedora/$REV/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
END
fi

JAVA_VERSION=25
JAVA_PKG=$([ "$DIST" = "fedora" ] && [ "$REV" -ge 44 ] && echo "jre-${JAVA_VERSION}-headless" || echo "java-${JAVA_VERSION}-openjdk-headless")
DOTNET_VERSION="10.0"
${package_manager} ${WEAK_OPT} -y install $([ "$DIST" != "fedora" ] && echo "epel-release") \
			python3 \
			nodejs \
			aspnetcore-runtime-${DOTNET_VERSION} \
			opensearch-${OPENSEARCH_VERSION} \
			mysql-community-server \
			rabbitmq-server \
			${REDIS_PACKAGE} \
			SDL2 \
			expect \
			${JAVA_PKG} \
			--enablerepo=opensearch-3.x ${DNF_NOGPG} ${CRB_REPO}

# Set Java ${JAVA_VERSION} as the default version
JAVA_PATH=$(find /usr/lib/jvm/ -name "java" -path "*java-${JAVA_VERSION}*" | head -1)
alternatives --install /usr/bin/java java "$JAVA_PATH" 100 && alternatives --set java "$JAVA_PATH"

# Add repo and install Fluent Bit.
if [ "${INSTALL_FLUENT_BIT}" == "true" ]; then 
	[ "$DIST" != "fedora" ] && run_remote_bash "https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh" || yum -y install fluent-bit
	${package_manager} -y install opensearch-dashboards-"${DASHBOARDS_VERSION}" --enablerepo=opensearch-dashboards-3.x ${DNF_NOGPG}
fi

if ! command -v semanage &> /dev/null; then
	yum install -y policycoreutils-python || yum install -y policycoreutils-python-utils
fi 

if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled && [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
	if [ "${ALLOW_HTTPD_T_PERMISSIVE:-false}" = "true" ]; then
		semanage permissive -a httpd_t
	else
		echo "Warning: SELinux is enforcing. Not making httpd_t permissive automatically; set ALLOW_HTTPD_T_PERMISSIVE=true only if AVC logs show it is required." >&2
	fi
fi

package_services="rabbitmq-server ${REDIS_PACKAGE} mysqld"

# Only adopted standalone Docs keeps its existing PostgreSQL configuration.
PRESERVE_DOCS_POSTGRESQL=false
if { [ -f "/etc/${package_sysname}/documentserver/nginx/ds.conf.apps.bak" ] \
	|| [ -f "/etc/${package_sysname}/documentserver/nginx/ds.conf.ssl.bak" ]; } \
	&& rpm -q postgresql-server >/dev/null 2>&1; then
	PRESERVE_DOCS_POSTGRESQL=true
fi
if [ "$INSTALLATION_TYPE" != "community" ] \
	&& [ "${PRESERVE_DOCS_POSTGRESQL}" != "true" ]; then
	{ yum check-update postgresql; PSQLExitCode=$?; } || true
	${package_manager} -y install postgresql postgresql-server
	if [[ $PSQLExitCode -eq $UPDATE_AVAILABLE_CODE ]]; then
		yum -y install postgresql-upgrade
		postgresql-setup --upgrade || true
	fi
	postgresql-setup --initdb || true

	sed -E -i "s/(host\s+(all|replication)\s+all\s+(127\.0\.0\.1\/32|\:\:1\/128)\s+)(ident|trust|md5)/\1scram-sha-256/" /var/lib/pgsql/data/pg_hba.conf
	sed -i "s/^#\?password_encryption = .*/password_encryption = 'scram-sha-256'/" /var/lib/pgsql/data/postgresql.conf

	package_services+=" postgresql"
fi
