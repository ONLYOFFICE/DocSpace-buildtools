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
{ yum check-update $DIST*-release; exitCode=$?; } || true #Checking for distribution update

UPDATE_AVAILABLE_CODE=100
if [[ $exitCode -eq $UPDATE_AVAILABLE_CODE ]]; then
	res_unsupported_version
	echo $RES_UNSPPORTED_VERSION
	echo $RES_SELECT_INSTALLATION
	echo $RES_ERROR_REMINDER
	echo $RES_QUESTIONS
	read_unsupported_installation
fi

if rpm -qa | grep mariadb.*config >/dev/null 2>&1; then
   echo $RES_MARIADB && exit 0
fi

#Add repositories: EPEL, REMI and RPMFUSION
[ "$DIST" != "fedora" ] && { rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-$REV.noarch.rpm || true; }
rpm -ivh https://rpms.remirepo.net/$REMI_DISTR_NAME/remi-release-$REV.rpm || true
yum localinstall -y --nogpgcheck https://download1.rpmfusion.org/free/$RPMFUSION_DISTR_NAME/rpmfusion-free-release-$REV.noarch.rpm

[ "$REV" = "9" ] && update-crypto-policies --set DEFAULT:SHA1
if [ "$DIST" == "centos" ]; then
	[ "$REV" = "9" ] && TESTING_REPO="--enablerepo=crb" || POWERTOOLS_REPO="--enablerepo=powertools"
elif [ "$DIST" == "redhat" ]; then
	/usr/bin/crb enable
fi

#add rabbitmq & erlang repo
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | bash

#add nodejs repo
NODE_VERSION="18"
curl -fsSL https://rpm.nodesource.com/setup_${NODE_VERSION}.x | sed '/update -y/d' | bash - || true

#add mysql repo
dnf remove -y @mysql && dnf module -y reset mysql && dnf module -y disable mysql
MYSQL_REPO_VERSION="$(curl https://repo.mysql.com | grep -oP "mysql80-community-release-${MYSQL_DISTR_NAME}${REV}-\K.*" | grep -o '^[^.]*' | sort | tail -n1)"
yum localinstall -y https://repo.mysql.com/mysql80-community-release-${MYSQL_DISTR_NAME}${REV}-${MYSQL_REPO_VERSION}.noarch.rpm || true

if ! yum repolist enabled | grep -q mysql-innovation-community; then
    sudo yum-config-manager --enable mysql-innovation-community
fi

if ! rpm -q mysql-community-server; then
	MYSQL_FIRST_TIME_INSTALL="true";
fi

#add opensearch repo
curl -SL https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/opensearch-2.x.repo -o /etc/yum.repos.d/opensearch-2.x.repo
ELASTIC_VERSION="2.11.1"

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

${package_manager} -y install $([ $DIST != "fedora" ] && echo "epel-release") \
			python3 \
			nodejs ${NODEJS_OPTION} \
			dotnet-sdk-8.0 \
			opensearch-${ELASTIC_VERSION} --enablerepo=opensearch-2.x \
			mysql-community-server \
			postgresql \
			postgresql-server \
			rabbitmq-server$rabbitmq_version \
			redis --enablerepo=remi \
			SDL2 $POWERTOOLS_REPO \
			expect \
			ffmpeg $TESTING_REPO

if [[ $PSQLExitCode -eq $UPDATE_AVAILABLE_CODE ]]; then
	yum -y install postgresql-upgrade
	postgresql-setup --upgrade || true
fi
postgresql-setup initdb	|| true

if ! command -v semanage &> /dev/null; then
	yum install -y policycoreutils-python || yum install -y policycoreutils-python-utils
fi 

semanage permissive -a httpd_t

package_services="rabbitmq-server postgresql redis mysqld"
