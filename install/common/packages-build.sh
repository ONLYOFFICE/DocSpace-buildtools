#!/bin/bash
set -e
set -x

PACKAGE_TYPE=$1
BUILD_PATH=$2
PRODUCT=$3
CLENT_PATH=${BUILD_PATH}/client
SERVER_PATH=${BUILD_PATH}/server
BUILDTOOLS_PATH=${BUILD_PATH}/buildtools

# Deleting unused files
find ${SERVER_PATH} -type d -name "runtimes" | \
while IFS= read -r RUNTIMES_DIR; do \
     find "$RUNTIMES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "linux-x64" ! -name "linux-arm64" -exec rm -rf {} \; ; \
done
find ${BUILD_PATH}/**/publish/ \
        -depth -type f -regex '.*\(eslintrc.*\|npmignore\|gitignore\|gitattributes\|gitmodules\|un~\|DS_Store\)' -exec rm -f {} \;
find ${BUILDTOOLS_PATH}/config -type f -regex '.*\.\(test\|dev\)\..*' -delete
rm -f ${BUILDTOOLS_PATH}/config/nginx/onlyoffice-login.conf

# Renaming files
find ${BUILDTOOLS_PATH}/install/common -type f -exec rename -f -v "s/product([^\/]*)$/${PRODUCT}\$1/g" {} ';'
rename -f -v 's/(.*\.(community|enterprise|developer))\.json$/$1.json.template/' ${BUILDTOOLS_PATH}/config/*.json

# Change directories
if ! grep -q 'var/www/${PRODUCT}' ${BUILDTOOLS_PATH}/config/nginx/*.conf; then find ${BUILDTOOLS_PATH}/config/nginx/ -name "*.conf" -exec sed -i "s@\(var/www/\)@\1${PRODUCT}/@" {} +; fi
sed -i "s#\$public_root#/var/www/${PRODUCT}/public/#g" ${BUILDTOOLS_PATH}/config/nginx/onlyoffice.conf
sed "s_\(.*root\).*;_\1 \"/var/www/${PRODUCT}\";_g" -i ${BUILDTOOLS_PATH}/install/docker/config/nginx/letsencrypt.conf
sed -i 's_app/onlyoffice/data_var/www/onlyoffice/Data_g' ${BUILDTOOLS_PATH}/config/*.json.template

# Configuring ${PRODUCT} services  
json -I -f "${BUILDTOOLS_PATH}/config/appsettings.services.json" \
     -e "this.logPath=\"/var/log/onlyoffice/${PRODUCT}\"" \
     -e "this.socket={ 'path': '../ASC.Socket.IO/' }" \
     -e "this.ssoauth={ 'path': '../ASC.SsoAuth/' }" \
     -e "this.logLevel=\"warning\"" \
     -e "this.core={ 'products': { 'folder': '/var/www/${PRODUCT}/products', 'subfolder': 'server'} }"
json -I -f "${BUILDTOOLS_PATH}/config/appsettings.json" \
     -e "this.core.notify.postman=\"services\"" \
     -e "this['debug-info'].enabled=\"false\"" \
     -e "this.web.samesite=\"None\"" \
     -e "this.core.oidc.disableValidateToken=\"false\"" \
     -e "this.core.oidc.showPII=\"false\""
json -I -f "${BUILDTOOLS_PATH}/config/apisystem.json" \
    -e "this.core.notify.postman=\"services\""
json -I -f "${CLENT_PATH}/public/scripts/config.json" \
    -e "this.wrongPortalNameUrl=\"\""
sed 's_\(minlevel=\)"[^"]*"_\1"Warn"_g' -i "${BUILDTOOLS_PATH}/config/nlog.config"
sed 's/teamlab.info/onlyoffice.com/g' -i ${BUILDTOOLS_PATH}/config/autofac.consumers.json

# Configuring proxy and router
sed -e 's_etc/nginx_etc/openresty_g' \
    -e 's/listen\s\+\([0-9]\+\);/listen 127.0.0.1:\1;/g' \
    -i ${BUILDTOOLS_PATH}/config/nginx/*.conf ${BUILDTOOLS_PATH}/config/nginx/includes/*.conf
sed -E 's_(http://)[^:]+(:5601)_\1localhost\2_g' -i ${BUILDTOOLS_PATH}/config/nginx/onlyoffice.conf
sed -e 's/\$router_host/127.0.0.1/g' \
    -e 's/this_host\|proxy_x_forwarded_host/host/g' \
    -e 's/proxy_x_forwarded_proto/scheme/g' \
    -e 's_includes_/etc/openresty/includes_g' \
    -e '/quic\|alt-svc/Id' \
    -i ${BUILDTOOLS_PATH}/install/docker/config/nginx/onlyoffice-proxy*.conf
sed -e '/.pid/d' \
    -e '/temp_path/d' \
    -e 's_etc/nginx_etc/openresty_g' \
    -e 's/\.log/-openresty.log/g' \
    -i ${BUILDTOOLS_PATH}/install/docker/config/nginx/templates/nginx.conf.template
mv -f ${BUILDTOOLS_PATH}/install/docker/config/nginx/onlyoffice-proxy-ssl.conf ${BUILDTOOLS_PATH}/install/docker/config/nginx/onlyoffice-proxy-ssl.conf.template
cp -rf ${BUILDTOOLS_PATH}/install/docker/config/nginx/onlyoffice-proxy.conf ${BUILDTOOLS_PATH}/install/docker/config/nginx/onlyoffice-proxy.conf.template

# Configuring fluent-bit
sed -i "s#\(/var/log/onlyoffice/\)#\1${PRODUCT}/#" ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\[INPUT]' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\    Name                exec' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\    Interval_Sec        86400' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\    Command             curl -s -X POST OPENSEARCH_SCHEME://OPENSEARCH_HOST:OPENSEARCH_PORT/OPENSEARCH_INDEX/_delete_by_query -H '\''Content-Type: application/json'\'' -d '\''{"query": {"range": {"@timestamp": {"lt": "now-30d"}}}}'\''' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\\' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
