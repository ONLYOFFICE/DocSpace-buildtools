#!/bin/bash
set -xe

PACKAGE_TYPE=$1
BUILD_PATH=$2
PRODUCT=$3
VERSION=$4
PACKAGE_SYSNAME=onlyoffice
PRODUCT_DIR=/var/www/${PACKAGE_SYSNAME}/${PRODUCT}
CLIENT_PATH=${BUILD_PATH}/client
SERVER_PATH=${BUILD_PATH}/server
BUILDTOOLS_PATH=${BUILD_PATH}/buildtools
PUBLISH_DIR=${BUILD_PATH}/publish

# Frontend build
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=4096}"
echo "== Frontend build =="; FRONTEND_START_TIMER=$(date +%s)
cd ${CLIENT_PATH}; pnpm install
GITHUB_STEP_SUMMARY='' pnpm run deploy; FRONTEND_END_TIMER=$(date +%s)
echo "::notice::Frontend build completed in $((FRONTEND_END_TIMER - FRONTEND_START_TIMER)) seconds"

# Backend build
echo "== Backend build =="; BACKEND_START_TIMER=$(date +%s)
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 MSBUILDDISABLENODEREUSE=1
cd ${SERVER_PATH}
PUBLISH_ARGS='-c Release --self-contained false -p:DebugType=None -p:DebugSymbols=false -p:UseAppHost=false'
dotnet publish common/Tools/ASC.Migration.Runner/ASC.Migration.Runner.csproj $PUBLISH_ARGS -o ${PUBLISH_DIR}/services/ASC.Migration.Runner/service/
dotnet publish ASC.Web.slnx $PUBLISH_ARGS -p:PublishProfile=ReleaseProfile
# The node services keep only production dependencies: the lockfile is checked first, then dev dependencies are dropped
for NODE_SERVICE in ASC.Socket.IO ASC.AI.Chat ASC.SsoAuth; do
  cd "${SERVER_PATH}/common/${NODE_SERVICE}"
  yarn install --immutable
  yarn workspaces focus --production
  mv -f "${SERVER_PATH}/common/${NODE_SERVICE}" ${PUBLISH_DIR}/services/
done
cd "${SERVER_PATH}/common/ASC.Identity" && mkdir -p ${PUBLISH_DIR}/services/{ASC.Identity.Registration,ASC.Identity.Authorization}
mvn -B dependency:go-offline -Dorg.slf4j.simpleLogger.defaultLogLevel=warn
mvn clean package -B -DskipTests -pl authorization/authorization-container,registration/registration-container -am
mv -f ${SERVER_PATH}/common/ASC.Identity/authorization/authorization-container/target/*.jar ${PUBLISH_DIR}/services/ASC.Identity.Authorization/app.jar
mv -f ${SERVER_PATH}/common/ASC.Identity/registration/registration-container/target/*.jar ${PUBLISH_DIR}/services/ASC.Identity.Registration/app.jar
mv -f ${SERVER_PATH}/LICENSE ${BUILD_PATH}/LICENSE
BACKEND_END_TIMER=$(date +%s)
echo "::notice::Backend build completed in $((BACKEND_END_TIMER - BACKEND_START_TIMER)) seconds"

# MCP build
cd "${BUILD_PATH}/mcp"
# The mcp repo has no packageManager field; pin pnpm to the version from its mise.toml
MCP_PNPM_VERSION=$(sed -nE 's/^pnpm *=[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' mise.toml 2>/dev/null || true)
[ -n "${MCP_PNPM_VERSION}" ] || { MCP_PNPM_VERSION=10.11.0; echo "::warning::pnpm version not found in mcp mise.toml, using ${MCP_PNPM_VERSION}"; }
corepack prepare "pnpm@${MCP_PNPM_VERSION}" --activate
# Allow postinstall scripts for MCP deps: esbuild and unrs-resolver
pnpm install --frozen-lockfile --dangerously-allow-all-builds
pnpm build-app
mkdir -p "${PUBLISH_DIR}/services/ASC.AI.MCP/service"
cp -a bin "${PUBLISH_DIR}/services/ASC.AI.MCP/service/"

# Deleting unused files
rm -rf ${PUBLISH_DIR}/services/{ASC.Socket.IO,ASC.AI.Chat,ASC.SsoAuth}/.yarn
rm -f ${PUBLISH_DIR}/services/{ASC.Socket.IO,ASC.AI.Chat,ASC.SsoAuth}/{.yarnrc.yml,yarn.lock}
rm -f ${PUBLISH_DIR}/services/ASC.AI.Chat/{onlyoffice-ai-chat-*.tgz,.prettierrc.json,.prettierignore,README.md,Dockerfile,Procfile}
# unix and linux hold the Linux builds of some packages (System.Data.Odbc, System.IO.Ports, ...), the host loads them on x64 and arm64
find ${PUBLISH_DIR} -type d -name "runtimes" | \
while IFS= read -r RUNTIMES_DIR; do \
     find "$RUNTIMES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "linux-x64" ! -name "linux-arm64" ! -name "linux" ! -name "unix" -exec rm -rf {} \; ; \
done
find ${PUBLISH_DIR} -depth -type f -regex '.*\(eslintrc.*\|npmignore\|gitignore\|gitattributes\|gitmodules\|un~\|DS_Store\)' -exec rm -f {} \;
find ${BUILDTOOLS_PATH}/config -type f -regex '.*\.\(test\|dev\)\..*' -delete
rm -f ${BUILDTOOLS_PATH}/config/nginx/onlyoffice-{login,management}.conf
# Source maps, type declarations inside node_modules and debug symbols are not needed at runtime; AI.Chat runs its .ts sources, they stay
# find runs on its own so that set -e stops the build when a delete fails; the list file only feeds the counts
STRIP_LIST=$(mktemp)
find "${PUBLISH_DIR}" -regextype posix-extended -type f \( -regex '.*\.(js|mjs|cjs|css|ts|mts|cts)\.map' -o -name '*.pdb' -o \( -path '*/node_modules/*' -regex '.*\.d\.[cm]?ts' \) \) -print -delete > "${STRIP_LIST}"
echo "::notice::Removed $(wc -l < "${STRIP_LIST}") source maps, type declarations and debug symbols"
# Translation tool metadata (locales/.meta), the client build skips it too
find "${PUBLISH_DIR}" -type d -path '*/locales/.meta' -prune -print -exec rm -rf {} + > "${STRIP_LIST}"
echo "::notice::Removed $(wc -l < "${STRIP_LIST}") locales/.meta folders"
rm -f "${STRIP_LIST}"

# NuGet packages that several .NET services use go once into dotnetstore (package dotnet-store); the services find them through additionalProbingPaths
python3 "${BUILDTOOLS_PATH}/install/common/dotnet-store.py" --store "${PUBLISH_DIR}/dotnetstore" --probing-path "${PRODUCT_DIR}/dotnetstore" \
     "${PUBLISH_DIR}"/services/{ASC.AI,ASC.AI.Worker,ASC.ApiSystem,ASC.ClearEvents,ASC.Data.Backup,ASC.Data.Backup.Worker,ASC.Files,ASC.Files.Worker}/service \
     "${PUBLISH_DIR}"/services/{ASC.Migration.Runner,ASC.Notify,ASC.People,ASC.Studio.Notify,ASC.TelegramService,ASC.Web.Api,ASC.Web.HealthChecks.UI,ASC.Web.Studio}/service

# The Next.js apps ship the same pnpm node_modules: one copy goes into web/node_modules (package node-modules, installed three levels above products/<product>/<app>)
SHARED_NODE_MODULES="${PUBLISH_DIR}/web/node_modules"
mkdir -p "${SHARED_NODE_MODULES}"
for NEXT_APP in login editor sdk management; do
  APP_DIR="${PUBLISH_DIR}/web/${NEXT_APP}"
  rsync -a --ignore-existing "${APP_DIR}/node_modules/" "${SHARED_NODE_MODULES}/"
  # The apps trace different subsets of a package, so the shared copy is their union; a file that differs between apps stops the build
  if diff -rq --no-dereference "${APP_DIR}/node_modules" "${SHARED_NODE_MODULES}" | grep -v "^Only in ${SHARED_NODE_MODULES}"; then
    echo "::error::${NEXT_APP}/node_modules differs from the shared node_modules"; exit 1
  fi
  # The app keeps no node_modules folder (an upgrade cannot turn a packaged folder into a link); its pnpm links go three levels further up instead
  while IFS= read -r LINK; do
    TARGET=$(readlink "${LINK}")
    RESOLVED=$(realpath -m -s "$(dirname "${LINK}")/${TARGET}")
    case "${RESOLVED}" in
      "${APP_DIR}/node_modules/"*)
        [ -e "${SHARED_NODE_MODULES}/${RESOLVED#"${APP_DIR}/node_modules/"}" ] || { echo "::error::${LINK} -> ${TARGET} has no target in the shared node_modules"; exit 1; }
        ln -sfn "../../../${TARGET}" "${LINK}" ;;
    esac
  done < <(find "${APP_DIR}" -path "${APP_DIR}/node_modules" -prune -o -type l -print)
  rm -rf "${APP_DIR}/node_modules"
done
echo "::notice::Shared node_modules of the Next.js apps: $(find "${SHARED_NODE_MODULES}" -type f | wc -l) files, $(du -sm "${SHARED_NODE_MODULES}" | cut -f1) MB"

# Renaming files
find ${BUILDTOOLS_PATH}/install/common -type f -exec rename -f -v "s/product([^\/]*)$/${PRODUCT}\$1/g" {} ';'
rename -f -v 's/(.*\.(community|enterprise|developer))\.json$/$1.json.template/' ${BUILDTOOLS_PATH}/config/*.json

# Change directories
if ! grep -q "${PRODUCT_DIR#/}" ${BUILDTOOLS_PATH}/config/nginx/*.conf; then find ${BUILDTOOLS_PATH}/config/nginx/ -name "*.conf" -exec sed -i "s@\(var/www/\)@\1${PACKAGE_SYSNAME}/${PRODUCT}/@" {} +; fi
sed -i "s#\$public_root#${PRODUCT_DIR}/public/#g" ${BUILDTOOLS_PATH}/config/nginx/onlyoffice.conf
sed "s_\(.*root\).*;_\1 \"${PRODUCT_DIR}\";_g" -i ${BUILDTOOLS_PATH}/install/docker/config/nginx/proxy/letsencrypt.conf
sed -i 's_app/onlyoffice/data_var/www/onlyoffice/Data_g' ${BUILDTOOLS_PATH}/config/*.json.template

# Configuring ${PRODUCT} services  
json -I -f "${BUILDTOOLS_PATH}/config/appsettings.services.json" \
     -e "this.logPath=\"/var/log/onlyoffice/${PRODUCT}\"" \
     -e "this.socket={ 'path': '../ASC.Socket.IO/' }" \
     -e "this.ssoauth={ 'path': '../ASC.SsoAuth/' }" \
     -e "this.logLevel=\"warning\"" \
     -e "this.core={ 'products': { 'folder': '${PRODUCT_DIR}/products', 'subfolder': 'server'} }"
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
    -e 's_includes_/etc/openresty/includes_g' \
    -i ${BUILDTOOLS_PATH}/install/docker/config/nginx/proxy/onlyoffice-proxy*.conf
sed -e '/.pid/d' \
    -e '/temp_path/d' \
    -e 's_etc/nginx_etc/openresty_g' \
    -e 's/\.log/-openresty.log/g' \
    -i ${BUILDTOOLS_PATH}/install/docker/config/nginx/nginx.conf.template
rename -f -v 's/\.conf$/.conf.template/' ${BUILDTOOLS_PATH}/install/docker/config/nginx/proxy/onlyoffice-proxy*.conf

# Configuring fluent-bit
sed -i "s#\(/var/log/onlyoffice/\)#\1${PRODUCT}/#" ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\[INPUT]' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\    Name                exec' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\    Interval_Sec        86400' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\    Command             curl -s -X POST OPENSEARCH_SCHEME://OPENSEARCH_HOST:OPENSEARCH_PORT/OPENSEARCH_INDEX/_delete_by_query -H '\''Content-Type: application/json'\'' -d '\''{"query": {"range": {"@timestamp": {"lt": "now-30d"}}}}'\''' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 
sed -i '/^\[OUTPUT\]/i\\' ${BUILDTOOLS_PATH}/install/docker/config/fluent-bit.conf 

rm -rf ${CLIENT_PATH} ${SERVER_PATH} # Cleaning up build directories (error: No space left on device)
