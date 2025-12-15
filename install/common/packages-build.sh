#!/bin/bash
set -xe

PACKAGE_TYPE=$1
BUILD_PATH=$2
PRODUCT=$3
VERSION=$4
CLIENT_PATH=${BUILD_PATH}/client
SERVER_PATH=${BUILD_PATH}/server
BUILDTOOLS_PATH=${BUILD_PATH}/buildtools
PUBLISH_DIR=${BUILD_PATH}/publish

# Frontend build
echo "== Frontend build =="; FRONTEND_START_TIMER=$(date +%s)
cd ${CLIENT_PATH}; pnpm install; pnpm build; pnpm run deploy; FRONTEND_END_TIMER=$(date +%s)
echo "::notice::Frontend build completed in $((FRONTEND_END_TIMER - FRONTEND_START_TIMER)) seconds"

# Backend build
echo "== Backend build =="; BACKEND_START_TIMER=$(date +%s)
cd ${SERVER_PATH}
dotnet build ASC.Web.slnf
dotnet build ASC.Migrations.sln --property:OutputPath=${PUBLISH_DIR}/services/ASC.Migration.Runner/service/
dotnet publish ASC.Web.slnf -p PublishProfile=ReleaseProfile
cd "${SERVER_PATH}/common/ASC.Socket.IO" && yarn install --frozen-lockfile && mv -f ${SERVER_PATH}/common/ASC.Socket.IO ${PUBLISH_DIR}/services/
cd "${SERVER_PATH}/common/ASC.SsoAuth" && yarn install --frozen-lockfile && mv -f ${SERVER_PATH}/common/ASC.SsoAuth ${PUBLISH_DIR}/services/
cd "${SERVER_PATH}/common/ASC.Identity" && mkdir -p ${PUBLISH_DIR}/services/{ASC.Identity.Registration,ASC.Identity.Authorization}
mvn -B dependency:go-offline -Dorg.slf4j.simpleLogger.defaultLogLevel=warn
mvn clean package -B -DskipTests -pl authorization/authorization-container -am
mvn clean package -B -DskipTests -pl registration/registration-container -am
mv -f ${SERVER_PATH}/common/ASC.Identity/authorization/authorization-container/target/*.jar ${PUBLISH_DIR}/services/ASC.Identity.Authorization/app.jar
mv -f ${SERVER_PATH}/common/ASC.Identity/registration/registration-container/target/*.jar ${PUBLISH_DIR}/services/ASC.Identity.Registration/app.jar
mv -f ${SERVER_PATH}/LICENSE ${BUILD_PATH}/LICENSE
BACKEND_END_TIMER=$(date +%s)
echo "::notice::Backend build completed in $((BACKEND_END_TIMER - BACKEND_START_TIMER)) seconds"

# MCP build
cd "${BUILD_PATH}/mcp"
pnpm install && pnpm run build-app
mkdir -p "${PUBLISH_DIR}/services/ASC.AI.MCP/service"
cp -a bin "${PUBLISH_DIR}/services/ASC.AI.MCP/service/"

# Deleting unused files
find ${PUBLISH_DIR} -type d -name "runtimes" | \
while IFS= read -r RUNTIMES_DIR; do \
     find "$RUNTIMES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "linux-x64" ! -name "linux-arm64" -exec rm -rf {} \; ; \
done
find ${PUBLISH_DIR} -depth -type f -regex '.*\(eslintrc.*\|npmignore\|gitignore\|gitattributes\|gitmodules\|un~\|DS_Store\)' -exec rm -f {} \;
find ${BUILDTOOLS_PATH}/config -type f -regex '.*\.\(test\|dev\)\..*' -delete
rm -f ${BUILDTOOLS_PATH}/config/nginx/onlyoffice-{login,management}.conf

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
     -e "this.core.oidc.showPII=\"false\"" \
     -e "this.version.number=\"${VERSION}\"" \
     -e "this.ai.mcp[0].endpoint='http://localhost:5158/mcp'"

json -I -f "${BUILDTOOLS_PATH}/config/apisystem.json" \
    -e "this.core.notify.postman=\"services\""
json -I -f "${CLIENT_PATH}/public/scripts/config.json" \
    -e "this.wrongPortalNameUrl=\"\""
sed -i '/ZiggyCreatures/! s_\(minlevel=\)"[^"]*"_\1"Warn"_g' "${BUILDTOOLS_PATH}/config/nlog.config"
sed -i '/weixinRedirectUrl/!s/teamlab.info/onlyoffice.com/g' ${BUILDTOOLS_PATH}/config/autofac.consumers.json

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
rename -f -v 's/\.conf$/.conf.template/' ${BUILDTOOLS_PATH}/install/docker/config/nginx/onlyoffice-proxy*.conf

# Configuring fluent-bit
sed -i "s#\(/var/log/onlyoffice/\)#\1${PRODUCT}/#" ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\[INPUT]' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\    Name                exec' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\    Interval_Sec        86400' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\    Command             curl -s -X POST OPENSEARCH_SCHEME://OPENSEARCH_HOST:OPENSEARCH_PORT/OPENSEARCH_INDEX/_delete_by_query -H '\''Content-Type: application/json'\'' -d '\''{"query": {"range": {"@timestamp": {"lt": "now-30d"}}}}'\''' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\\' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 

rm -rf ${CLIENT_PATH} ${SERVER_PATH} # Cleaning up build directories (error: No space left on device)
