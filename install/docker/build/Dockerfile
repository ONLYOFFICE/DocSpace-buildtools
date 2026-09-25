# syntax=docker/dockerfile:1-labs

ARG PRODUCT=onlyoffice
ARG SRC_PATH="/app/onlyoffice/src"
ARG BUILD_PATH="/var/www"
ARG DOTNET_SDK="mcr.microsoft.com/dotnet/sdk:10.0"
ARG DOTNET_RUN="mcr.microsoft.com/dotnet/aspnet:10.0-noble"
ARG BUSYBOX_VERSION="1.37"
ARG PYTHON_VERSION="3.12-slim"
ARG NODE_VERSION="24.16-trixie-slim"
ARG OPENRESTY_VERSION="1.31.1.1-2"
ARG PLUGIN_NODE_TYPES_VERSION="18.19.0"
ARG JAVA_VERSION="25"
ARG JAVA_RUN_VERSION="${JAVA_VERSION}-jre"
ARG MAVEN_VERSION="3.9-eclipse-temurin-${JAVA_VERSION}"

# Image resources
FROM --platform=$BUILDPLATFORM python:${PYTHON_VERSION} AS src
ARG GIT_BRANCH="master"
ARG FALLBACK_BRANCH="develop"
ARG SRC_PATH="/app/onlyoffice/src"
ARG BUILD_PATH="/var/www"
ARG PRODUCT_VERSION=0.0.0
ARG BUILD_NUMBER=0
ARG DEBUG_INFO="true"

ARG BUILDTOOLS_REPO="https://github.com/ONLYOFFICE/DocSpace-buildtools.git"
ARG SERVER_REPO="https://github.com/ONLYOFFICE/DocSpace-Server.git"
ARG CLIENT_REPO="https://github.com/ONLYOFFICE/DocSpace-Client.git"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    git curl; \
    rm -rf /var/lib/apt/lists/*

RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN sh -ec '\
    curl --retry 3 --retry-delay 2 --retry-connrefused -fsSL \
      -H "Accept: application/vnd.github+json" \
      ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
      "https://api.github.com/repos/ONLYOFFICE/DocSpace-buildtools/git/refs/heads/${GIT_BRANCH}" -o version.json'

# BEGIN_SOURCE
RUN <<'EOF'
#!/bin/bash
    set -e

    git_clone() {
        local REPO=$1 DEST=$2 EXTRA_OPTS=$3 FALLBACK=${4:-$FALLBACK_BRANCH}
        local BRANCH=$(git ls-remote --exit-code --heads "${REPO}" "${GIT_BRANCH}" > /dev/null 2>&1 && echo "${GIT_BRANCH}" || echo "${FALLBACK}")
        git clone ${EXTRA_OPTS} -b "${BRANCH}" "${REPO}" "${DEST}"
    }

    PIDS=()
    DEPTH=$([[ "${DEBUG_INFO,,}" =~ ^(true|1|yes)$ ]] && echo 30 || echo 1)
    git_clone "${BUILDTOOLS_REPO}" "${SRC_PATH}/buildtools" "--recurse-submodules --depth ${DEPTH}" & PIDS+=($!)
    git_clone "${SERVER_REPO}"     "${SRC_PATH}/server"     "--recurse-submodules --depth ${DEPTH}" & PIDS+=($!)
    git_clone "${CLIENT_REPO}"     "${SRC_PATH}/client"     "--recurse-submodules --depth ${DEPTH}" & PIDS+=($!)
    git_clone https://github.com/ONLYOFFICE/docspace-plugins.git "${SRC_PATH}/plugins" "--depth 1" master & PIDS+=($!)
    git_clone https://github.com/ONLYOFFICE/ASC.Web.Campaigns.git "${SRC_PATH}/campaigns" "--depth 1" master & PIDS+=($!)

    for PID in "${PIDS[@]}"; do wait "${PID}" || exit 1; done
EOF
# END_SOURCE

WORKDIR ${SRC_PATH}/buildtools/config
RUN <<EOF
#!/bin/bash
    mkdir -p /app/onlyoffice/config/ && \
    ls | grep -Ev 'test|\.dev\.|nginx' | xargs cp -r -t /app/onlyoffice/config/
    cd ${SRC_PATH}
    mkdir -p /etc/nginx/conf.d && cp -f buildtools/config/nginx/onlyoffice*.conf /etc/nginx/conf.d/
    mkdir -p /etc/nginx/includes/ && cp -f buildtools/config/nginx/includes/onlyoffice*.conf /etc/nginx/includes/ && cp -f buildtools/config/nginx/includes/server-*.conf /etc/nginx/includes/
    sed -i "s/\"number\".*,/\"number\": \"${PRODUCT_VERSION}.${BUILD_NUMBER}\",/g" /app/onlyoffice/config/appsettings.json
#    sed -e 's/#//' -i /etc/nginx/conf.d/onlyoffice.conf
    if [[ "${DEBUG_INFO,,}" =~ ^(true|1|yes)$ ]]; then
        pip install --no-cache-dir -r ${SRC_PATH}/buildtools/requirements.txt --break-system-packages && \
        python3 ${SRC_PATH}/buildtools/debuginfo.py && \
        pip cache purge
    fi
    find ${SRC_PATH}/buildtools/install/docker -name "*.sh" -exec chmod +x {} +
    find ${SRC_PATH} -name '.git' -type d -prune -exec rm -rf {} +
EOF

# .net build
FROM --platform=$BUILDPLATFORM $DOTNET_SDK AS build-dotnet
ARG DEBIAN_FRONTEND=noninteractive
ARG SRC_PATH

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1
ENV MSBUILDDISABLENODEREUSE=1

WORKDIR ${SRC_PATH}/server
COPY --from=src ${SRC_PATH}/server/ .

RUN PUBLISH_ARGS='-c Release --self-contained false -p:DebugType=None -p:DebugSymbols=false -p:UseAppHost=false' && \
    for PAIR in "linux-x64:amd64" "linux-arm64:arm64"; do \
        RID="${PAIR%%:*}"; ARCH="${PAIR##*:}"; \
        dotnet publish common/Tools/ASC.Migration.Runner/ASC.Migration.Runner.csproj $PUBLISH_ARGS -r "$RID" -o "${SRC_PATH}/publish/services/ASC.Migration.Runner/service/" && \
        dotnet publish ASC.Web.slnx $PUBLISH_ARGS -r "$RID" -p:PublishProfile=ReleaseProfile && \
        mv ${SRC_PATH}/publish ${SRC_PATH}/publish-${ARCH} || exit 1; \
    done && \
    dotnet nuget locals all --clear && \
    rm -rf ${SRC_PATH}/server

# node build
FROM node:${NODE_VERSION} AS build-node-services
ARG SRC_PATH
WORKDIR ${SRC_PATH}/server
COPY --from=src ${SRC_PATH}/server/common/ASC.Socket.IO ./common/ASC.Socket.IO
COPY --from=src ${SRC_PATH}/server/common/ASC.SsoAuth ./common/ASC.SsoAuth
COPY --from=src ${SRC_PATH}/server/common/ASC.AI.Chat ./common/ASC.AI.Chat

RUN for svc in ASC.Socket.IO ASC.SsoAuth ASC.AI.Chat; do \
    (cd ${SRC_PATH}/server/common/$svc && yarn install --immutable); \
    done && \
    yarn cache clean --all && \
    find ${SRC_PATH}/server/common -type f \( -name "*.js.map" -o -name "*.css.map" \) -delete

# build frondend from client
FROM --platform=$BUILDPLATFORM node:${NODE_VERSION} AS build-node
ARG SRC_PATH
ARG BUILD_ARGS="build"
ARG DEPLOY_ARGS="deploy"

WORKDIR ${SRC_PATH}
COPY --from=src ${SRC_PATH}/buildtools/config ./buildtools/config
COPY --from=src ${SRC_PATH}/client/ ./client

WORKDIR ${SRC_PATH}/client
ENV PNPM_HOME=/tmp/pnpm
ENV NODE_OPTIONS="--max-old-space-size=4096"
# pnpm version comes from client/package.json "packageManager"; do not `corepack prepare pnpm@latest --activate`, it pins nothing.
RUN (command -v corepack >/dev/null || npm install -g corepack) && \
    corepack enable && \
    pnpm install && \
    pnpm ${BUILD_ARGS} && \
    pnpm run ${DEPLOY_ARGS} && \
    find ${SRC_PATH}/publish/web -type f \( -name "*.js.map" -o -name "*.css.map" \) -delete && \
    rm -rf "$(pnpm store path)" /root/.cache ${SRC_PATH}/client ${SRC_PATH}/buildtools

RUN find "${SRC_PATH}/publish/web" -mindepth 4 -maxdepth 4 -name ".next" -type d | \
    while IFS= read -r NEXT_DIR; do \
        APP_NAME=$(basename "$(dirname "$NEXT_DIR")") && \
        mkdir -p "${SRC_PATH}/publish/static/${APP_NAME}/static" && \
        cp -a "${NEXT_DIR}/static/chunks" "${NEXT_DIR}/static/css" "${NEXT_DIR}/static/media" \
            "${SRC_PATH}/publish/static/${APP_NAME}/static/" ; \
    done

# build plugins
FROM --platform=$BUILDPLATFORM node:${NODE_VERSION} AS build-plugins
ARG SRC_PATH
ARG PLUGIN_NODE_TYPES_VERSION
ENV PLUGIN_NODE_TYPES_VERSION=${PLUGIN_NODE_TYPES_VERSION}

COPY --from=src ${SRC_PATH}/plugins ${SRC_PATH}/plugins
COPY --from=src ${SRC_PATH}/buildtools/install/common/plugins-build.sh ${SRC_PATH}/buildtools/install/common/plugins-build.sh
WORKDIR ${SRC_PATH}/buildtools/install/common
RUN apt-get -y update && \
    apt-get install --no-install-recommends -yq unzip jq && \
    mkdir -p "${SRC_PATH}/plugins/publish" && \
    bash plugins-build.sh "${SRC_PATH}/plugins" && \
    find "${SRC_PATH}/plugins" -mindepth 1 -maxdepth 1 ! -name "publish" -exec rm -rf {} + && \
    rm -rf ${SRC_PATH}/buildtools

# java build
FROM --platform=$BUILDPLATFORM maven:${MAVEN_VERSION} AS build-java
ARG SRC_PATH

WORKDIR ${SRC_PATH}/server/common/ASC.Identity/
COPY --from=src ${SRC_PATH}/server/common/ASC.Identity/ .

RUN mkdir -p ${SRC_PATH}/publish/services/ASC.Identity.Registration && \
    mkdir -p ${SRC_PATH}/publish/services/ASC.Identity.Authorization && \
    mkdir -p ${SRC_PATH}/publish/services/ASC.Identity.minified && \
    mvn -Dmaven.repo.local=/tmp/m2/repository -B dependency:go-offline && \
    mvn -Dmaven.repo.local=/tmp/m2/repository clean package -B -DskipTests -pl authorization/authorization-container,registration/registration-container -am && \
    mvn clean package -Pminified -DskipTests -Dfmt.skip=true -T1 -pl minified -am -B && \
    mv -f ${SRC_PATH}/server/common/ASC.Identity/authorization/authorization-container/target/*.jar ${SRC_PATH}/publish/services/ASC.Identity.Authorization/app.jar && \
    mv -f ${SRC_PATH}/server/common/ASC.Identity/registration/registration-container/target/*.jar ${SRC_PATH}/publish/services/ASC.Identity.Registration/app.jar && \
    mv -f ${SRC_PATH}/server/common/ASC.Identity/minified/target/*.jar ${SRC_PATH}/publish/services/ASC.Identity.minified/app.jar && \
    rm -rf ${SRC_PATH}/server /tmp/m2

FROM $DOTNET_RUN AS dotnetrun
ARG BUILD_PATH
ARG SRC_PATH
ARG TARGETARCH
ENV BUILD_PATH=${BUILD_PATH}
ENV SRC_PATH=${SRC_PATH}
ENV TARGETARCH=${TARGETARCH}
ENV APP_STORAGE_ROOT=/app/onlyoffice/data/ \
    LOG_DIR=/var/log/onlyoffice \
    PATH_TO_CONF=/app/onlyoffice/config

RUN apt-get -y update && \
    apt-get install --no-install-recommends -yq adduser nano curl libgdiplus iproute2 python3-requests python3-netaddr python3-jsonpath-ng && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -uid 104 --quiet --home /var/www/onlyoffice --system --gid 107 onlyoffice && \
    mkdir -p /var/log/onlyoffice /app/onlyoffice/data && \
    chown -R onlyoffice:onlyoffice /app/onlyoffice /var/log /var/www /run && \
    rm -rf /var/lib/apt/lists/* /tmp/*

COPY --from=src --chown=onlyoffice:onlyoffice /app/onlyoffice/config /app/onlyoffice/config/
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/entrypoints/docker-entrypoint.py /usr/bin/docker-entrypoint.py

USER onlyoffice
EXPOSE 5050
ENTRYPOINT ["python3", "/usr/bin/docker-entrypoint.py"]

FROM node:${NODE_VERSION} AS noderun
ARG BUILD_PATH
ARG SRC_PATH
ENV BUILD_PATH=${BUILD_PATH}
ENV SRC_PATH=${SRC_PATH}
ENV APP_STORAGE_ROOT=/app/onlyoffice/data/ \
    LOG_DIR=/var/log/onlyoffice \
    PATH_TO_CONF=/app/onlyoffice/config

RUN apt-get -y update && \
    apt-get install --no-install-recommends -yq adduser nano curl iproute2 python3-requests python3-netaddr python3-jsonpath-ng && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -uid 104 --quiet --home /var/www/onlyoffice --system --gid 107 onlyoffice && \
    mkdir -p /var/log/onlyoffice /app/onlyoffice/data /var/www /run && \
    chown -R onlyoffice:onlyoffice /app/onlyoffice /var/log /var/www /run && \
    rm -rf /var/lib/apt/lists/* /tmp/*

COPY --from=src --chown=onlyoffice:onlyoffice /app/onlyoffice/config /app/onlyoffice/config/
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/entrypoints/docker-entrypoint.py /usr/bin/docker-entrypoint.py
USER onlyoffice
EXPOSE 5050
ENTRYPOINT ["python3", "/usr/bin/docker-entrypoint.py"]

FROM eclipse-temurin:${JAVA_RUN_VERSION} AS javarun
ARG BUILD_PATH
ARG SRC_PATH
ENV BUILD_PATH=${BUILD_PATH}
ENV LOG_DIR=/var/log/onlyoffice

RUN apt-get -y update && \
    apt-get install --no-install-recommends -yq adduser nano curl && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -uid 104 --quiet --home /var/www/onlyoffice --system --gid 107 onlyoffice && \
    mkdir -p /var/log/onlyoffice /var/www/onlyoffice && \
    chown -R onlyoffice:onlyoffice /var/log /var/www /run && \
    rm -rf /var/lib/apt/lists/* /tmp/*

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/entrypoints/docker-identity-entrypoint.sh /usr/bin/docker-identity-entrypoint.sh
USER onlyoffice
ENTRYPOINT ["/bin/bash", "/usr/bin/docker-identity-entrypoint.sh"]

## Nginx router otel lua dependencies ##
# Built on the -fat flavour of the same OpenResty release the router runs, so
# the native pb.so is linked against the LuaJIT ABI that ships at runtime.
FROM openresty/openresty:${OPENRESTY_VERSION}-bullseye-fat AS otel-build
# Git tags and the luarocks registry are both mutable, so every dependency is
# fetched as a tarball and checked against a pinned sha256 before it is used.
# Refresh a checksum with: curl -sL <url> | sha256sum
ARG OPENTELEMETRY_LUA_VERSION=0.2.6
ARG OPENTELEMETRY_LUA_SHA256=645259acbc5af7f5b374fdad102c961584aa831a20a7bc392e34ec557acf6314
ARG LUA_RESTY_HTTP_VERSION=0.16.1
ARG LUA_RESTY_HTTP_SHA256=d2f867ea8cacb406172d258ba5c17ca530b5deff56d58583e6c11f4f190be015
ARG LUA_PROTOBUF_VERSION=0.3.3
ARG LUA_PROTOBUF_SHA256=5df24cbff460d40a1de770486cb0cc74e0e0dd6950d9c61ec97559d2f5c504ef

RUN set -eu; \
    fetch_verified() { \
        curl -fsSL -o /tmp/dep.tar.gz "$1"; \
        echo "$2  /tmp/dep.tar.gz" | sha256sum -c -; \
        tar -xzf /tmp/dep.tar.gz -C /tmp; \
        rm -f /tmp/dep.tar.gz; \
    }; \
    fetch_verified https://github.com/starwing/lua-protobuf/archive/refs/tags/${LUA_PROTOBUF_VERSION}.tar.gz ${LUA_PROTOBUF_SHA256}; \
    cd /tmp/lua-protobuf-${LUA_PROTOBUF_VERSION}; \
    rockspec="$(find rockspecs -name "lua-protobuf-${LUA_PROTOBUF_VERSION}-*.rockspec" | sort | tail -1)"; \
    test -n "$rockspec" || { echo "no rockspec for lua-protobuf ${LUA_PROTOBUF_VERSION}" >&2; exit 1; }; \
    /usr/local/openresty/luajit/bin/luarocks make "$rockspec"; \
    cd /; \
    mkdir -p /usr/local/openresty/site/lualib/resty; \
    fetch_verified https://github.com/yangxikun/opentelemetry-lua/archive/refs/tags/v${OPENTELEMETRY_LUA_VERSION}.tar.gz ${OPENTELEMETRY_LUA_SHA256}; \
    cp -r /tmp/opentelemetry-lua-${OPENTELEMETRY_LUA_VERSION}/lib/opentelemetry /usr/local/openresty/site/lualib/; \
# otel/init.lua hands the exporter the bare collector URL because http_client.new
# is where the /v1/traces suffix comes from. Fail the build if a version bump ever
# changes that, rather than silently posting every span to the wrong path.
    /usr/local/openresty/luajit/bin/luajit -e 'package.loaded["resty.http"] = {}; package.path = "/usr/local/openresty/site/lualib/?.lua;" .. package.path; local client = require("opentelemetry.trace.exporter.http_client"); local uri = client.new("http://collector:4318", 1, {}).uri; assert(uri == "http://collector:4318/v1/traces", "opentelemetry-lua http_client.new no longer appends /v1/traces, it built " .. uri)'; \
    fetch_verified https://github.com/ledgetech/lua-resty-http/archive/refs/tags/v${LUA_RESTY_HTTP_VERSION}.tar.gz ${LUA_RESTY_HTTP_SHA256}; \
    cp -r /tmp/lua-resty-http-${LUA_RESTY_HTTP_VERSION}/lib/resty/. /usr/local/openresty/site/lualib/resty/; \
    rm -rf /tmp/*

## Nginx image ##
FROM openresty/openresty:${OPENRESTY_VERSION}-bullseye AS router
ARG SRC_PATH
ARG BUILD_PATH
ARG COUNT_WORKER_CONNECTIONS=1024

ENV DNS_NAMESERVER=127.0.0.11 \
    COUNT_WORKER_CONNECTIONS=$COUNT_WORKER_CONNECTIONS \
    MAP_HASH_BUCKET_SIZE=""

RUN mkdir -p /var/log/nginx/ && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -uid 104 --quiet --home /var/www/onlyoffice --system --gid 107 onlyoffice && \
    chown -R onlyoffice:onlyoffice /etc/nginx/ /var/ /usr/ /run/ /var/log/nginx/

# copy static services files and config values 
COPY --from=src --chown=onlyoffice:onlyoffice /etc/nginx/conf.d /etc/nginx/conf.d
COPY --from=src --chown=onlyoffice:onlyoffice /etc/nginx/includes /etc/nginx/includes
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/client ${BUILD_PATH}/client
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/public ${BUILD_PATH}/public
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/static ${BUILD_PATH}/build
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/config/nginx/html /etc/nginx/html
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/campaigns/src/campaigns ${BUILD_PATH}/public/campaigns
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/router/docker-entrypoint.d /docker-entrypoint.d
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/router/docker-entrypoint.sh /usr/bin/docker-entrypoint.sh
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/nginx.conf.template /etc/nginx/nginx.conf.template
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/router/templates/upstream.conf.template /etc/nginx/templates/upstream.conf.template
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/entrypoints/prepare-nginx-router.sh /docker-entrypoint.d/prepare-nginx-router.sh

# opentelemetry tracing: lua sdk + deps and the otel nginx wiring
COPY --from=otel-build --chown=onlyoffice:onlyoffice /usr/local/openresty/site/lualib /usr/local/openresty/site/lualib
COPY --from=otel-build --chown=onlyoffice:onlyoffice /usr/local/openresty/luajit/lib/lua/5.1 /usr/local/openresty/luajit/lib/lua/5.1
COPY --from=otel-build --chown=onlyoffice:onlyoffice /usr/local/openresty/luajit/share/lua/5.1 /usr/local/openresty/luajit/share/lua/5.1
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/config/nginx/lua /etc/nginx/lua
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/router/otel.conf /etc/nginx/conf.d/00-otel.conf

# changes for upstream configure
RUN sed -i 's/127.0.0.1:5010/$service_api_system/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5012/$service_backup/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5007/$service_files/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5004/$service_people_server/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5000/$service_api/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5003/$service_studio/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5157/$service_ai/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9899/$service_socket/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9837/$service_ai_chat/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9834/$service_sso/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5013/$service_doceditor/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5099/$service_sdk/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5011/$service_login/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9090/$service_identity_api/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:8080/$service_identity/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5015/$service_management/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5033/$service_healthchecks/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5601/$dashboards_host:5601/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/$public_root/\/var\/www\/public\//' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/http:\/\/172.*/$document_server;/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i '/client_body_temp_path/ i \ \ \ \ $MAP_HASH_BUCKET_SIZE' /etc/nginx/nginx.conf.template && \
    sed -i 's/\(worker_connections\).*;/\1 $COUNT_WORKER_CONNECTIONS;/' /etc/nginx/nginx.conf.template && \
    sed -i -e '/^user/s/^/#/' -e 's#/tmp/nginx.pid#nginx.pid#' -e 's#/etc/nginx/mime.types#mime.types#' /etc/nginx/nginx.conf.template

USER onlyoffice

ENTRYPOINT  [ "/usr/bin/docker-entrypoint.sh" ]

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]

## Management ##
FROM noderun AS management
WORKDIR ${BUILD_PATH}/products/ASC.Management/management
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/management/ .

CMD ["server.js", "ASC.Management"]

## Sdk ##
FROM noderun AS sdk
WORKDIR ${BUILD_PATH}/products/ASC.Sdk/sdk
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/sdk/ .

CMD ["server.js", "ASC.Sdk"]

## Doceditor ##
FROM noderun AS doceditor
WORKDIR ${BUILD_PATH}/products/ASC.Editors/editor
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/editor/ .

CMD ["server.js", "ASC.Editors"]

## Login ##
FROM noderun AS login
WORKDIR ${BUILD_PATH}/products/ASC.Login/login
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/login/ .

CMD ["server.js", "ASC.Login"]

## ASC.Data.Backup.Worker ##
FROM dotnetrun AS backup_worker
WORKDIR ${BUILD_PATH}/services/ASC.Data.Backup.Worker/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Data.Backup.Worker/service/  .

CMD ["ASC.Data.Backup.Worker.dll", "ASC.Data.Backup.Worker", "core:eventBus:subscriptionClientName=asc_event_bus_backup_queue"]

# ASC.ApiSystem ##
FROM dotnetrun AS api_system
WORKDIR ${BUILD_PATH}/services/ASC.ApiSystem/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.ApiSystem/service/  .

CMD ["ASC.ApiSystem.dll", "ASC.ApiSystem"]

## ASC.ClearEvents ##
FROM dotnetrun AS clear-events
WORKDIR ${BUILD_PATH}/services/ASC.ClearEvents/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.ClearEvents/service/  .

CMD ["ASC.ClearEvents.dll", "ASC.ClearEvents"]

## ASC.Data.Backup ##
FROM dotnetrun AS backup
WORKDIR ${BUILD_PATH}/services/ASC.Data.Backup/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Data.Backup/service/ .

CMD ["ASC.Data.Backup.dll", "ASC.Data.Backup"]

## ASC.Files ##
FROM dotnetrun AS files
WORKDIR ${BUILD_PATH}/products/ASC.Files/server/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Files/service/ .

CMD ["ASC.Files.dll", "ASC.Files"]

## ASC.Files.Worker ##
FROM dotnetrun AS files_worker
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
WORKDIR ${BUILD_PATH}/products/ASC.Files/service/
USER root

COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Files.Worker/service/ .

# Copy ffmpeg binary and essential libraries
COPY --from=onlyoffice/ffvideo:7.1 --chown=onlyoffice:onlyoffice /app/src/ /
RUN set -eux; \
  PKGS="libasound2t64 libv4l-0t64 libxml2 libgomp1"; \
  [ "$TARGETARCH" = "amd64" ] && PKGS="$PKGS libx11-xcb1 libxcb-dri3-0 libxcb-shape0 libxcb-xfixes0 libxfixes3 ocl-icd-libopencl1"; \
  apt-get update && apt-get install -y --no-install-recommends $PKGS && rm -rf /var/lib/apt/lists/* /tmp/*

USER onlyoffice

CMD ["ASC.Files.Worker.dll", "ASC.Files.Worker", "core:eventBus:subscriptionClientName=asc_event_bus_files_service_queue"]

## ASC.Notify ##
FROM dotnetrun AS notify
WORKDIR ${BUILD_PATH}/services/ASC.Notify/service
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Notify/service/ .

CMD ["ASC.Notify.dll", "ASC.Notify", "core:eventBus:subscriptionClientName=asc_event_bus_notify_queue"]

## ASC.People ##
FROM dotnetrun AS people_server
WORKDIR ${BUILD_PATH}/products/ASC.People/server/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.People/service/ .

CMD ["ASC.People.dll", "ASC.People"]

## ASC.AI ##
FROM dotnetrun AS ai
WORKDIR ${BUILD_PATH}/products/ASC.AI/server/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.AI/service/ .

CMD ["ASC.AI.dll", "ASC.AI"]

## ASC.AI.Worker ##
FROM dotnetrun AS ai_worker
WORKDIR ${BUILD_PATH}/products/ASC.AI/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.AI.Worker/service/ .

CMD ["ASC.AI.Worker.dll", "ASC.AI.Worker", "core:eventBus:subscriptionClientName=asc_event_bus_ai_service_queue"] 

## ASC.Socket.IO ##
FROM noderun AS socket
WORKDIR ${BUILD_PATH}/services/ASC.Socket.IO/
COPY --from=build-node-services --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.Socket.IO .

CMD  ["server.js", "ASC.Socket.IO"]

## ASC.AI.Chat ##
FROM noderun AS ai-chat
WORKDIR ${BUILD_PATH}/services/ASC.AI.Chat/
COPY --from=build-node-services --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.AI.Chat .

CMD  ["server.js", "ASC.AI.Chat"]

## ASC.SsoAuth ##
FROM noderun AS ssoauth
WORKDIR ${BUILD_PATH}/services/ASC.SsoAuth/
COPY --from=build-node-services --chown=onlyoffice:onlyoffice  ${SRC_PATH}/server/common/ASC.SsoAuth .

CMD ["app.js", "ASC.SsoAuth"]

## ASC.Studio.Notify ##
FROM dotnetrun AS studio_notify
WORKDIR ${BUILD_PATH}/services/ASC.Studio.Notify/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Studio.Notify/service/ .

CMD ["ASC.Studio.Notify.dll", "ASC.Studio.Notify", "core:eventBus:subscriptionClientName=asc_event_bus_studio_notify_queue"]

## ASC.Web.Api ##
FROM dotnetrun AS api
WORKDIR ${BUILD_PATH}/studio/ASC.Web.Api/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Web.Api/service/ .

CMD ["ASC.Web.Api.dll", "ASC.Web.Api"]

## ASC.Web.Studio ##
FROM dotnetrun AS studio
WORKDIR ${BUILD_PATH}/studio/ASC.Web.Studio/
COPY --from=build-plugins --chown=onlyoffice:onlyoffice ${SRC_PATH}/plugins/publish/ ${BUILD_PATH}/studio/plugins
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Web.Studio/service/ .

CMD ["ASC.Web.Studio.dll", "ASC.Web.Studio", "core:eventBus:subscriptionClientName=asc_event_bus_webstudio_queue"]

## ASC.Web.HealthChecks.UI ##
FROM dotnetrun AS healthchecks
WORKDIR ${BUILD_PATH}/services/ASC.Web.HealthChecks.UI/service

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/entrypoints/docker-healthchecks-entrypoint.sh /usr/bin/docker-healthchecks-entrypoint.sh
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Web.HealthChecks.UI/service/ .

ENTRYPOINT ["/bin/bash", "/usr/bin/docker-healthchecks-entrypoint.sh"]
CMD ["ASC.Web.HealthChecks.UI.dll", "ASC.Web.HealthChecks.UI"]

## ASC.TelegramService ##
FROM dotnetrun AS telegram
WORKDIR ${BUILD_PATH}/services/ASC.TelegramService/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.TelegramService/service/ .

CMD ["ASC.TelegramService.dll", "ASC.TelegramService", "core:eventBus:subscriptionClientName=asc_event_bus_telegram_queue"]

## ASC.Migration.Runner ##
FROM dotnetrun AS onlyoffice-migration-runner
WORKDIR ${BUILD_PATH}/services/ASC.Migration.Runner/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/entrypoints/docker-migration-entrypoint.sh /usr/bin/docker-migration-entrypoint.sh
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Migration.Runner/service/ .

ENTRYPOINT ["/bin/bash", "/usr/bin/docker-migration-entrypoint.sh"]

## ASC.Identity.Authorization ##
FROM javarun AS identity-authorization
WORKDIR ${BUILD_PATH}/services/ASC.Identity.Authorization/
COPY --from=build-java --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Identity.Authorization/app.jar .
CMD ["ASC.Identity.Authorization"]

## ASC.Identity.Registration ##
FROM javarun AS identity-api
WORKDIR ${BUILD_PATH}/services/ASC.Identity.Registration/
COPY --from=build-java --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Identity.Registration/app.jar .
CMD ["ASC.Identity.Registration"]

## image for k8s bin-share ##
FROM busybox:${BUSYBOX_VERSION} AS bin_share
ARG SRC_PATH
ARG BUILD_PATH
RUN mkdir -p /app/ASC.Files/server && \
    mkdir -p /app/ASC.People/server && \
    mkdir -p /app/ASC.AI/server && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -u 104 onlyoffice --home /var/www/onlyoffice --system -G onlyoffice
USER onlyoffice
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/entrypoints/bin-share-docker-entrypoint.sh /usr/bin/docker-entrypoint.sh
COPY --from=files --chown=onlyoffice:onlyoffice ${BUILD_PATH}/products/ASC.Files/server/ /app/ASC.Files/server/
COPY --from=people_server --chown=onlyoffice:onlyoffice ${BUILD_PATH}/products/ASC.People/server/ /app/ASC.People/server/
COPY --from=ai --chown=onlyoffice:onlyoffice ${BUILD_PATH}/products/ASC.AI/server/ /app/ASC.AI/server/
ENTRYPOINT ["/bin/sh", "/usr/bin/docker-entrypoint.sh"]

## image for k8s wait-bin-share ##
FROM busybox:${BUSYBOX_VERSION} AS wait_bin_share
ARG SRC_PATH
RUN addgroup --system --gid 107 onlyoffice && \
    adduser -u 104 onlyoffice --home /var/www/onlyoffice --system -G onlyoffice && \
    mkdir /app
USER onlyoffice
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/entrypoints/wait-bin-share-docker-entrypoint.sh /usr/bin/docker-entrypoint.sh
ENTRYPOINT ["/bin/sh", "/usr/bin/docker-entrypoint.sh"]

## Dotnet Services ##
FROM dotnetrun AS dotnet-services
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends supervisor && \
    mkdir -p /var/log/supervisor && chown -R onlyoffice:onlyoffice /var/log/supervisor && \
    rm -rf /var/lib/apt/lists/*

ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Files.Worker/service/ ${BUILD_PATH}/products/ASC.Files/service/

COPY --from=onlyoffice/ffvideo:7.1 --chown=onlyoffice:onlyoffice /app/src/ /
RUN set -eux; \
  PKGS="libasound2t64 libv4l-0t64 libxml2 libgomp1"; \
  [ "$TARGETARCH" = "amd64" ] && PKGS="$PKGS libx11-xcb1 libxcb-dri3-0 libxcb-shape0 libxcb-xfixes0 libxfixes3 ocl-icd-libopencl1"; \
  apt-get update && apt-get install -y --no-install-recommends $PKGS && rm -rf /var/lib/apt/lists/* /tmp/*

USER onlyoffice

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/supervisor/stack/dotnet_services.conf /etc/supervisor/conf.d/supervisord.conf
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/supervisor/stack/start-after-migration.py /usr/local/bin/start-after-migration.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.AI/service/ ${BUILD_PATH}/products/ASC.AI/server/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.AI.Worker/service/ ${BUILD_PATH}/products/ASC.AI/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.ApiSystem/service/  ${BUILD_PATH}/services/ASC.ApiSystem/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.ClearEvents/service/  ${BUILD_PATH}/services/ASC.ClearEvents/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Data.Backup/service/ ${BUILD_PATH}/services/ASC.Data.Backup/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Data.Backup.Worker/service/  ${BUILD_PATH}/services/ASC.Data.Backup.Worker/service
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Files/service/ ${BUILD_PATH}/products/ASC.Files/server/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Migration.Runner/service/ ${BUILD_PATH}/services/ASC.Migration.Runner/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Notify/service/ ${BUILD_PATH}/services/ASC.Notify/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.People/service/ ${BUILD_PATH}/products/ASC.People/server/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Studio.Notify/service/ ${BUILD_PATH}/services/ASC.Studio.Notify/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.TelegramService/service/ ${BUILD_PATH}/services/ASC.TelegramService/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Web.Api/service/ ${BUILD_PATH}/services/ASC.Web.Api/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Web.HealthChecks.UI/service/ ${BUILD_PATH}/services/ASC.Web.HealthChecks.UI/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Web.Studio/service/ ${BUILD_PATH}/services/ASC.Web.Studio/service/
COPY --from=build-plugins --chown=onlyoffice:onlyoffice ${SRC_PATH}/plugins/publish/ ${BUILD_PATH}/studio/plugins

CMD ["supervisord", "-n"]

## Node Services ##
FROM noderun AS node-services
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends supervisor && \
    mkdir -p /var/log/supervisor && chown -R onlyoffice:onlyoffice /var/log/supervisor && \
    rm -rf /var/lib/apt/lists/*
USER onlyoffice

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/supervisor/stack/node_services.conf /etc/supervisor/conf.d/supervisord.conf
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/editor/ ${BUILD_PATH}/products/ASC.Editors/editor/
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/login/ ${BUILD_PATH}/products/ASC.Login/login/
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/management/ ${BUILD_PATH}/products/ASC.Management/management/
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/sdk/ ${BUILD_PATH}/products/ASC.Sdk/sdk/
COPY --from=build-node-services --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.Socket.IO ${BUILD_PATH}/services/ASC.Socket.IO/
COPY --from=build-node-services --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.AI.Chat ${BUILD_PATH}/services/ASC.AI.Chat/
COPY --from=build-node-services --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.SsoAuth ${BUILD_PATH}/services/ASC.SsoAuth/

CMD ["supervisord", "-n"]

## Java Services ##
FROM javarun AS java-services
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends supervisor && \
    mkdir -p /var/log/supervisor && chown -R onlyoffice:onlyoffice /var/log/supervisor && \
    rm -rf /var/lib/apt/lists/*
USER onlyoffice

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/supervisor/stack/java_services.conf /etc/supervisor/conf.d/supervisord.conf
COPY --from=build-java --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Identity.Authorization/app.jar ${BUILD_PATH}/services/ASC.Identity.Authorization/app.jar
COPY --from=build-java --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Identity.Registration/app.jar ${BUILD_PATH}/services/ASC.Identity.Registration/app.jar

CMD ["supervisord", "-n"]

FROM onlyoffice/4testing-docspace-mcp:latest AS mcp

## Image standalone ##
FROM dotnetrun AS standalone
USER root

ARG DEBIAN_FRONTEND=noninteractive

ENV DNS_NAMESERVER=127.0.0.11 \
    COUNT_WORKER_CONNECTIONS=1024 \
    MAP_HASH_BUCKET_SIZE= ENV_EXTENSION=

RUN set -eux; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        mysql-client ca-certificates wget gnupg \
        gettext-base supervisor libcap2-bin certbot; \
    curl -fsSL https://github.com/trentm/json/raw/master/lib/json.js -o /usr/local/bin/json && chmod +x /usr/local/bin/json; \
    wget -qO- https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg; \
    echo "deb [arch=$TARGETARCH signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/$([ "$TARGETARCH" = arm64 ] && echo arm64/)ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") main" > /etc/apt/sources.list.d/openresty.list; \
    apt-get update && apt-get install -y --no-install-recommends openresty; \
    # let the unprivileged onlyoffice user bind :80, then prepare nginx dirs
    setcap 'cap_net_bind_service=+ep' /usr/local/openresty/nginx/sbin/nginx; \
    mkdir -p /var/log/nginx /var/log/openresty /var/log/supervisor /etc/nginx/conf.d /etc/nginx/includes /etc/nginx/templates /etc/letsencrypt /letsencrypt; \
    chown -R onlyoffice:onlyoffice /etc/nginx /var/log/nginx /var/log/openresty /var/log/supervisor /usr/local/openresty /etc/letsencrypt /letsencrypt; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /tmp/*

# Services config + entrypoint + supervisor config
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/standalone/docker-entrypoint.sh /docker-entrypoint.sh
# COPY --chown=onlyoffice:onlyoffice standalone/docker-entrypoint.sh /docker-entrypoint.sh
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/supervisor/standalone.conf /etc/supervisor/conf.d/supervisord.conf
# COPY --chown=onlyoffice:onlyoffice supervisor/standalone.conf /etc/supervisor/conf.d/supervisord.conf

# nginx config, static files, router scripts
COPY --from=src --exclude=onlyoffice-login.conf --exclude=onlyoffice-management.conf --chown=onlyoffice:onlyoffice /etc/nginx/conf.d /etc/nginx/conf.d
COPY --from=src --chown=onlyoffice:onlyoffice /etc/nginx/includes /etc/nginx/includes
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/config/nginx/html /etc/nginx/html
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/campaigns/src/campaigns ${BUILD_PATH}/public/campaigns
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/router/docker-entrypoint.d /docker-entrypoint.d
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/router/docker-entrypoint.sh /nginx/docker-entrypoint.sh
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/nginx.conf.template /etc/nginx/nginx.conf.template
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/build/entrypoints/prepare-nginx-router.sh /docker-entrypoint.d/prepare-nginx-router.sh
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/router/templates/standalone-upstream.conf.template /etc/nginx/templates/upstream.conf.template
# Same front-proxy configs the microservices proxy container and the DEB/RPM packages use; the RUN below adapts them the way packages-build.sh does.
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/proxy/onlyoffice-proxy.conf /app/onlyoffice/template/nginx/onlyoffice-proxy.conf
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/proxy/onlyoffice-proxy-ssl.conf /app/onlyoffice/template/nginx/onlyoffice-proxy-ssl.conf
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/proxy/letsencrypt.conf /etc/nginx/includes/letsencrypt.conf

# nodejs static and dynamic files
COPY --from=node:24-bookworm-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/ ${BUILD_PATH}/
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/static ${BUILD_PATH}/build
COPY --from=build-node-services --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.Socket.IO ${SRC_PATH}/publish/services/ASC.Socket.IO
COPY --from=build-node-services --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.SsoAuth ${SRC_PATH}/publish/services/ASC.SsoAuth
COPY --from=build-node-services --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.AI.Chat ${SRC_PATH}/publish/services/ASC.AI.Chat
COPY --from=build-plugins --chown=onlyoffice:onlyoffice ${SRC_PATH}/plugins/publish/ ${APP_STORAGE_ROOT}/Studio/webplugins

# .NET Monolith and Migration Runner, plugins
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Monolith/service ${SRC_PATH}/publish/services/backend/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Migration.Runner/service ${SRC_PATH}/publish/services/backend/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish-${TARGETARCH}/services/ASC.Files/service/DocStore/ ${SRC_PATH}/publish/services/backend/DocStore/

# java Identity (OAuth)
ENV JAVA_HOME=/opt/java
ENV PATH=/opt/java/bin:${PATH}

COPY --from=javarun /opt/java/openjdk /opt/java
COPY --from=build-java --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Identity.minified/app.jar ${SRC_PATH}/publish/services/ASC.Identity.minified/app.jar

# mcp
COPY --from=mcp --chown=onlyoffice:onlyoffice  /srv/onlyoffice-docspace-mcp/bin ${SRC_PATH}/publish/services/onlyoffice-apps-mcp/bin
COPY --from=mcp --chown=onlyoffice:onlyoffice  /srv/onlyoffice-docspace-mcp/LICENSE ${SRC_PATH}/publish/services/onlyoffice-apps-mcp/LICENSE

RUN set -eux; \
    sed -i -e 's#$public_root#/var/www/public/#' -e "/map \$scheme \$document_server {/,/}/ s|default \"http://[^\"]*\";|default \$document_server_vs_path;|" /etc/nginx/conf.d/onlyoffice.conf; \
    # route every .NET backend upstream to the single monolith port
    sed -i -E "s#default \"(http://127.0.0.1):(5000|5003|5004|5007|5010|5012|5157)\";#default \"\1:5051\";#g" "/etc/nginx/conf.d/onlyoffice.conf"; \
    sed -i 's#http://127.0.0.1:9090#http://127.0.0.1:8080#g' /etc/nginx/conf.d/onlyoffice.conf && \
    # The router runs in this same openresty, as in the DEB/RPM packages, and the main config sits under /usr/local/openresty, so relative includes would miss /etc/nginx.
    sed -i -e 's/\$router_host/127.0.0.1/g' -e 's#include includes/#include /etc/nginx/includes/#' /app/onlyoffice/template/nginx/onlyoffice-proxy.conf /app/onlyoffice/template/nginx/onlyoffice-proxy-ssl.conf && \
    # Paths are fixed in the shared config (proxy-ssl.yml bind-mounts a host cert there); the entrypoint envsubst's them per SSL_CERT_PATH/SSL_KEY_PATH instead, since standalone takes its certificate from a mounted directory, not a fixed host path.
    sed -i -e 's#ssl_certificate /usr/local/share/ca-certificates/tls.crt;#ssl_certificate ${SSL_CERTIFICATE};#' -e 's#ssl_certificate_key /etc/ssl/private/tls.key;#ssl_certificate_key ${SSL_CERTIFICATE_KEY};#' /app/onlyoffice/template/nginx/onlyoffice-proxy-ssl.conf && \
    { /usr/local/openresty/bin/openresty -V 2>&1 | grep -q http_v3_module || sed -i -e '/quic/d' -e "/alt-svc/d" /app/onlyoffice/template/nginx/onlyoffice-proxy-ssl.conf; } && \
    sed -i '/client_body_temp_path/ i \ \ \ \ $MAP_HASH_BUCKET_SIZE' /etc/nginx/nginx.conf.template && \
    sed -i 's/\(worker_connections\).*;/\1 $COUNT_WORKER_CONNECTIONS;/' /etc/nginx/nginx.conf.template && \
    sed -i -e '/^user/s/^/#/' -e 's#/tmp/nginx.pid#nginx.pid#' -e 's#/etc/nginx/mime.types#mime.types#' /etc/nginx/nginx.conf.template && \
    echo '{ "Redis": {} }' > /app/onlyoffice/config/redis.json && \
    echo '{ "RabbitMQ": {} }' > /app/onlyoffice/config/rabbitmq.json
    # Note: redis.json / rabbitmq.json are baked as empty objects in the image
    # (no Redis/RabbitMQ container in the standalone stack), so they are left as-is.

USER onlyoffice
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=5 \
    CMD supervisorctl status >/dev/null 2>&1 || exit 1; supervisorctl status | grep -qE 'FATAL|BACKOFF' && exit 1 || exit 0

ENTRYPOINT [ "/docker-entrypoint.sh" ]
