ARG SRC_PATH="/app/onlyoffice/src"
ARG BUILD_PATH="/var/www"
ARG DOTNET_SDK="mcr.microsoft.com/dotnet/sdk:10.0"
ARG DOTNET_RUN="mcr.microsoft.com/dotnet/aspnet:10.0-noble"

# Image resources
FROM python:3.12-slim AS src
ARG GIT_BRANCH="master"
ARG SRC_PATH
ARG BUILD_PATH
ARG PRODUCT_VERSION=0.0.0
ARG BUILD_NUMBER=0
ARG DEBUG_INFO="true"

ARG BUILDTOOLS_REPO="https://github.com/ONLYOFFICE/DocSpace-buildtools.git"
ARG SERVER_REPO="https://github.com/ONLYOFFICE/DocSpace-Server.git"
ARG CLIENT_REPO="https://github.com/ONLYOFFICE/DocSpace-Client.git"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    git ; \
    rm -rf /var/lib/apt/lists/*

ADD https://api.github.com/repos/ONLYOFFICE/DocSpace-buildtools/git/refs/heads/${GIT_BRANCH} version.json
RUN <<EOF
#!/bin/bash
echo "--- clone resources ---"

git clone --recurse-submodules -b $(echo "$(git ls-remote --exit-code --heads "${BUILDTOOLS_REPO}" "${GIT_BRANCH}"\
 > /dev/null 2>&1 && echo "${GIT_BRANCH}" || echo "master")") --depth 30 ${BUILDTOOLS_REPO} ${SRC_PATH}/buildtools && \

git clone --recurse-submodules -b $(echo "$(git ls-remote --exit-code --heads "${SERVER_REPO}" "${GIT_BRANCH}"\
 > /dev/null 2>&1 && echo "${GIT_BRANCH}" || echo "master")") --depth 30 ${SERVER_REPO} ${SRC_PATH}/server && \

git clone -b $(echo "$(git ls-remote --exit-code --heads "${CLIENT_REPO}" "${GIT_BRANCH}"\
 > /dev/null 2>&1 && echo "${GIT_BRANCH}" || echo "master")") --depth 30 ${CLIENT_REPO} ${SRC_PATH}/client && \

git clone -b "$( [ "$GIT_BRANCH" = develop ] && echo develop || echo master )" --depth 1 https://github.com/ONLYOFFICE/docspace-plugins.git ${SRC_PATH}/plugins && \
git clone -b "master" --depth 1 https://github.com/ONLYOFFICE/ASC.Web.Campaigns.git ${SRC_PATH}/campaigns
EOF

WORKDIR ${SRC_PATH}/buildtools/config
RUN <<EOF
    echo "--- customize config base files ---" && \
    mkdir -p /app/onlyoffice/config/ && \
    ls | grep -Ev 'test|\.dev\.|nginx' | xargs cp -r -t /app/onlyoffice/config/
    cd ${SRC_PATH}
    mkdir -p /etc/nginx/conf.d && cp -f buildtools/config/nginx/onlyoffice*.conf /etc/nginx/conf.d/
    mkdir -p /etc/nginx/includes/ && cp -f buildtools/config/nginx/includes/onlyoffice*.conf /etc/nginx/includes/ && cp -f buildtools/config/nginx/includes/server-*.conf /etc/nginx/includes/
    sed -i "s/\"number\".*,/\"number\": \"${PRODUCT_VERSION}.${BUILD_NUMBER}\",/g" /app/onlyoffice/config/appsettings.json
    sed -e 's/#//' -i /etc/nginx/conf.d/onlyoffice.conf
    if [ "$DEBUG_INFO" = true ]; then
        echo "--- add customized debuginfo ---" && \
        pip install -r ${SRC_PATH}/buildtools/requirements.txt --break-system-packages && \
        python3 ${SRC_PATH}/buildtools/debuginfo.py && \
        pip cache purge
    fi
EOF

# .net build
FROM $DOTNET_SDK AS build-dotnet
ARG DEBIAN_FRONTEND=noninteractive
ARG SRC_PATH

WORKDIR ${SRC_PATH}/server
COPY --from=src ${SRC_PATH}/server/ .

RUN echo "--- build/publish docspace-server .net 10.0 ---" && \
    dotnet build ASC.Web.slnf && \
    dotnet build ASC.Migrations.sln --property:OutputPath=${SRC_PATH}/publish/services/ASC.Migration.Runner/service/ && \
    dotnet publish ASC.Web.slnf -p PublishProfile=ReleaseProfile && \
    dotnet nuget locals all --clear && \
    rm -rf ${SRC_PATH}/server/*

# node build
FROM node:22-slim AS build-node
ARG SRC_PATH
ARG BUILD_ARGS="build"
ARG DEPLOY_ARGS="deploy"

# build services Socket, SsoAuth from DocSpace-server 
WORKDIR ${SRC_PATH}/server
COPY --from=src ${SRC_PATH}/server/common/ASC.Socket.IO ./common/ASC.Socket.IO
COPY --from=src ${SRC_PATH}/server/common/ASC.SsoAuth ./common/ASC.SsoAuth

RUN echo "--- build/publish ASC.Socket.IO ---" && \
    cd ${SRC_PATH}/server/common/ASC.Socket.IO && \
    yarn install --immutable && \
    echo "--- build/publish ASC.SsoAuth ---" && \ 
    cd ${SRC_PATH}/server/common/ASC.SsoAuth && \
    yarn install --immutable && \
    yarn cache clean --all

# build frondend from DocSpace-client
WORKDIR ${SRC_PATH}
COPY --from=src ${SRC_PATH}/buildtools/config ./buildtools/config
COPY --from=src ${SRC_PATH}/client/ ./client

WORKDIR ${SRC_PATH}/client
ENV PNPM_HOME=/tmp/pnpm
RUN echo "--- installing pnpm ---" && \
    npm install -g pnpm && \
    echo "--- build/publish docspace-client node ---" && \
    pnpm install && \
    pnpm ${BUILD_ARGS} && \
    pnpm run ${DEPLOY_ARGS} && \
    rm -rf ${SRC_PATH}/client ${SRC_PATH}/buildtools && \
    rm -rf /tmp/pnpm

# build plugins
FROM node:22-slim AS build-plugins
ARG SRC_PATH
COPY --from=src ${SRC_PATH}/plugins ${SRC_PATH}/plugins
WORKDIR ${SRC_PATH}/buildtools/install/common
COPY --from=src ${SRC_PATH}/buildtools/install/common/plugins-build.sh ./plugins-build.sh
RUN echo "--- build/publish plugins ---" && \
    apt-get update && apt-get install -y unzip && \
    bash plugins-build.sh "${SRC_PATH}/plugins" && \
    find "${SRC_PATH}/plugins" -mindepth 1 -maxdepth 1 ! -path "${SRC_PATH}/plugins/publish" -exec rm -rf {} + && \
    rm -rf ${SRC_PATH}/buildtools

# java build
FROM maven:3.9-eclipse-temurin-21 AS java-build
ARG SRC_PATH

WORKDIR ${SRC_PATH}/server/common/ASC.Identity/
COPY --from=src ${SRC_PATH}/server/common/ASC.Identity/ .

RUN echo "--- build/publish docspace-server java (ASC.Identity) ---" && \
    mkdir -p ${SRC_PATH}/publish/services/ASC.Identity.Registration && \
    mkdir -p ${SRC_PATH}/publish/services/ASC.Identity.Authorization && \
    mvn -Dmaven.repo.local=/tmp/m2/repository -B dependency:go-offline && \
    mvn -Dmaven.repo.local=/tmp/m2/repository clean package -B -DskipTests -pl authorization/authorization-container -am && \
    mvn -Dmaven.repo.local=/tmp/m2/repository clean package -B -DskipTests -pl registration/registration-container -am && \
    mv -f ${SRC_PATH}/server/common/ASC.Identity/authorization/authorization-container/target/*.jar ${SRC_PATH}/publish/services/ASC.Identity.Authorization/app.jar && \
    mv -f ${SRC_PATH}/server/common/ASC.Identity/registration/registration-container/target/*.jar ${SRC_PATH}/publish/services/ASC.Identity.Registration/app.jar && \
    rm -rf ${SRC_PATH}/server /tmp/m2

FROM $DOTNET_RUN AS dotnetrun
ARG BUILD_PATH
ARG SRC_PATH
ENV BUILD_PATH=${BUILD_PATH}
ENV SRC_PATH=${SRC_PATH}

# add defualt user and group for no-root run
RUN echo "--- install runtime aspnet.9 ---" && \
    mkdir -p /var/log/onlyoffice && \
    mkdir -p /app/onlyoffice/data && \
    apt-get -y update && \
    apt-get install -yq \
    sudo \
    adduser \
    nano \
    curl \
    supervisor \
    vim \
    python3-pip \
    libgdiplus && \
    pip3 install --upgrade --break-system-packages jsonpath-ng multipledispatch netaddr netifaces requests && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -uid 104 --quiet --home /var/www/onlyoffice --system --gid 107 onlyoffice && \
    chown onlyoffice:onlyoffice /app/onlyoffice -R && \
    chown onlyoffice:onlyoffice /var/log -R && \
    chown onlyoffice:onlyoffice /var/www -R && \
    chown onlyoffice:onlyoffice /run -R && \
    echo "--- clean up ---" && \
    rm -rf /var/lib/apt/lists/* \
    /tmp/*

COPY --from=src --chown=onlyoffice:onlyoffice /app/onlyoffice/config /app/onlyoffice/config/

USER onlyoffice
EXPOSE 5050
ENTRYPOINT ["python3", "docker-entrypoint.py"]

FROM node:22-slim AS noderun
ARG BUILD_PATH
ARG SRC_PATH 
ENV BUILD_PATH=${BUILD_PATH}
ENV SRC_PATH=${SRC_PATH}

RUN echo "--- install runtime node.22 ---" && \
    mkdir -p /var/log/onlyoffice && \
    mkdir -p /app/onlyoffice/data && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -uid 104 --quiet --home /var/www/onlyoffice --system --gid 107 onlyoffice && \
    chown onlyoffice:onlyoffice /app/onlyoffice -R && \
    chown onlyoffice:onlyoffice /var/log -R  && \
    chown onlyoffice:onlyoffice /var/www -R && \
    chown onlyoffice:onlyoffice /run -R && \
    apt-get -y update && \
    apt-get install -yq \ 
    sudo \
    nano \
    curl \
    vim \
    supervisor \
    python3-pip && \
    pip3 install --upgrade --break-system-packages jsonpath-ng multipledispatch netaddr netifaces requests && \
    echo "--- clean up ---" && \
    rm -rf \
    /var/lib/apt/lists/* \
    /tmp/*

COPY --from=src --chown=onlyoffice:onlyoffice /app/onlyoffice/config /app/onlyoffice/config/
USER onlyoffice
EXPOSE 5050
ENTRYPOINT ["python3", "docker-entrypoint.py"]

FROM eclipse-temurin:21-jre AS javarun
ARG BUILD_PATH
ARG SRC_PATH
ENV BUILD_PATH=${BUILD_PATH}

RUN echo "--- install runtime eclipse-temurin:21 ---" && \
    mkdir -p /var/log/onlyoffice && \
    mkdir -p /var/www/onlyoffice && \
    groupadd -g 107 onlyoffice && \
    useradd -u 104 -g onlyoffice -d /var/www/onlyoffice -s /bin/bash onlyoffice && \
    chown onlyoffice:onlyoffice /var/log -R && \
    chown onlyoffice:onlyoffice /var/www -R && \
    chown onlyoffice:onlyoffice /run -R && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    sudo \
    bash \
    nano \
    curl \
    supervisor && \
    echo "--- clean up ---" && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/*

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-identity-entrypoint.sh /usr/bin/docker-identity-entrypoint.sh
USER onlyoffice
ENTRYPOINT ["bash", "/usr/bin/docker-identity-entrypoint.sh"]

## Nginx image ##
FROM openresty/openresty:focal AS router
ARG SRC_PATH
ARG BUILD_PATH
ARG COUNT_WORKER_CONNECTIONS=1024
ENV DNS_NAMESERVER=127.0.0.11 \
    COUNT_WORKER_CONNECTIONS=$COUNT_WORKER_CONNECTIONS \
    MAP_HASH_BUCKET_SIZE=""

RUN echo "--- customize router openresty service ---" && \
    apt-get -y update && \
    apt-get install -yq vim && \
    mkdir -p /var/log/nginx/ && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -uid 104 --quiet --home /var/www/onlyoffice --system --gid 107 onlyoffice && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /usr/share/nginx/html/* && \
    chown -R onlyoffice:onlyoffice /etc/nginx/ && \
    chown -R onlyoffice:onlyoffice /var/ && \
    chown -R onlyoffice:onlyoffice /usr/ && \
    chown -R onlyoffice:onlyoffice /run/ && \
    chown -R onlyoffice:onlyoffice /var/log/nginx/

# copy static services files and config values 
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/client ${BUILD_PATH}/client
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/public ${BUILD_PATH}/public
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/editor/packages/doceditor/.next/static/chunks ${BUILD_PATH}/build/doceditor/static/chunks
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/editor/packages/doceditor/.next/static/css ${BUILD_PATH}/build/doceditor/static/css
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/editor/packages/doceditor/.next/static/media ${BUILD_PATH}/build/doceditor/static/media
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/login/packages/login/.next/static/chunks ${BUILD_PATH}/build/login/static/chunks
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/login/packages/login/.next/static/css ${BUILD_PATH}/build/login/static/css
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/login/packages/login/.next/static/media ${BUILD_PATH}/build/login/static/media
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/sdk/packages/sdk/.next/static/chunks ${BUILD_PATH}/build/sdk/static/chunks
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/sdk/packages/sdk/.next/static/css ${BUILD_PATH}/build/sdk/static/css
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/sdk/packages/sdk/.next/static/media ${BUILD_PATH}/build/sdk/static/media
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/management/packages/management/.next/static/chunks ${BUILD_PATH}/build/management/static/chunks
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/management/packages/management/.next/static/css ${BUILD_PATH}/build/management/static/css
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/management/packages/management/.next/static/media ${BUILD_PATH}/build/management/static/media
COPY --from=src --chown=onlyoffice:onlyoffice /etc/nginx/conf.d /etc/nginx/conf.d
COPY --from=src --chown=onlyoffice:onlyoffice /etc/nginx/includes /etc/nginx/includes
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/campaigns/src/campaigns ${BUILD_PATH}/public/campaigns
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/docker-entrypoint.d /docker-entrypoint.d
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/templates/upstream.conf.template /etc/nginx/templates/upstream.conf.template
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/templates/nginx.conf.template /etc/nginx/nginx.conf.template
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/config/nginx/html /etc/nginx/html
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/prepare-nginx-router.sh /docker-entrypoint.d/prepare-nginx-router.sh
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/docker-entrypoint.sh /docker-entrypoint.sh

USER onlyoffice

# changes for upstream configure
RUN sed -i 's/127.0.0.1:5010/$service_api_system/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5012/$service_backup/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5007/$service_files/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5004/$service_people_server/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5000/$service_api/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5003/$service_studio/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5157/$service_ai/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9899/$service_socket/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9834/$service_sso/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5013/$service_doceditor/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5099/$service_sdk/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5011/$service_login/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9090/$service_identity_api/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:8080/$service_identity/' /etc/nginx/conf.d/onlyoffice.conf && \
    if [[ -z "${SERVICE_CLIENT}" ]] ; then sed -i 's/127.0.0.1:5001/$service_client/' /etc/nginx/conf.d/onlyoffice.conf; fi && \
    sed -i 's/127.0.0.1:5015/$service_management/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5033/$service_healthchecks/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5601/$dashboards_host:5601/' /etc/nginx/includes/server-dashboards.conf && \
    sed -i 's/$public_root/\/var\/www\/public\//' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/http:\/\/172.*/$document_server;/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i '/client_body_temp_path/ i \ \ \ \ $MAP_HASH_BUCKET_SIZE' /etc/nginx/nginx.conf.template && \
    sed -i 's/\(worker_connections\).*;/\1 $COUNT_WORKER_CONNECTIONS;/' /etc/nginx/nginx.conf.template && \
    sed -i -e '/^user/s/^/#/' -e 's#/tmp/nginx.pid#nginx.pid#' -e 's#/etc/nginx/mime.types#mime.types#' /etc/nginx/nginx.conf.template 

ENTRYPOINT  [ "/docker-entrypoint.sh" ]

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]

## Management ##
FROM noderun AS management
WORKDIR ${BUILD_PATH}/products/ASC.Management/management

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/management/ .

CMD ["server.js", "ASC.Management"]

## Sdk ##
FROM noderun AS sdk
WORKDIR ${BUILD_PATH}/products/ASC.Sdk/sdk

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/sdk/ .

CMD ["server.js", "ASC.Sdk"]

## Doceditor ##
FROM noderun AS doceditor
WORKDIR ${BUILD_PATH}/products/ASC.Editors/editor

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/editor/ .

CMD ["server.js", "ASC.Editors"]

## Login ##
FROM noderun AS login
WORKDIR ${BUILD_PATH}/products/ASC.Login/login

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/login/ .

CMD ["server.js", "ASC.Login"]

## ASC.Data.Backup.BackgroundTasks ##
FROM dotnetrun AS backup_background
WORKDIR ${BUILD_PATH}/services/ASC.Data.Backup.BackgroundTasks/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Data.Backup.BackgroundTasks/service/  .

CMD ["ASC.Data.Backup.BackgroundTasks.dll", "ASC.Data.Backup.BackgroundTasks", "core:eventBus:subscriptionClientName=asc_event_bus_backup_queue"]

# ASC.ApiSystem ##
FROM dotnetrun AS api_system
WORKDIR ${BUILD_PATH}/services/ASC.ApiSystem/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.ApiSystem/service/  .

CMD ["ASC.ApiSystem.dll", "ASC.ApiSystem"]

## ASC.ClearEvents ##
FROM dotnetrun AS clear-events
WORKDIR ${BUILD_PATH}/services/ASC.ClearEvents/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.ClearEvents/service/  .

CMD ["ASC.ClearEvents.dll", "ASC.ClearEvents"]

## ASC.Data.Backup ##
FROM dotnetrun AS backup
WORKDIR ${BUILD_PATH}/services/ASC.Data.Backup/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Data.Backup/service/ .

CMD ["ASC.Data.Backup.dll", "ASC.Data.Backup"]

## ASC.Files ##
FROM dotnetrun AS files
WORKDIR ${BUILD_PATH}/products/ASC.Files/server/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Files/service/ .

CMD ["ASC.Files.dll", "ASC.Files"]

## ASC.Files.Service ##
FROM dotnetrun AS files_services
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
WORKDIR ${BUILD_PATH}/products/ASC.Files/service/
USER root

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Files.Service/service/ .
COPY --from=onlyoffice/ffvideo:7.1 --chown=onlyoffice:onlyoffice /app/src/ /

RUN <<EOF
    #!/bin/bash
    set -xe
    ARCH_LINUX=$(lscpu | grep Architecture | awk '{print $2}')
    echo "--- ADD necessary lib for arh: ${ARCH_LINUX} ---"
    if [ "$ARCH_LINUX" = "x86_64" ] ; then
        apt update && \
        apt install -y \
            libasound2t64 \
            libdrm2 \
            libv4l-0t64 \
            libplacebo-dev \
            libxcb-shape0 \
            ocl-icd-opencl-dev 
    fi
    if [ "$ARCH_LINUX" = "aarch64" ] ; then
        apt update && \
        apt install -y \
            libasound2t64 \
            libv4l-0t64
    fi 
    rm -rf /var/lib/apt/lists/* \
    /tmp/*
EOF

USER onlyoffice

CMD ["ASC.Files.Service.dll", "ASC.Files.Service", "core:eventBus:subscriptionClientName=asc_event_bus_files_service_queue"]

## ASC.Notify ##
FROM dotnetrun AS notify
WORKDIR ${BUILD_PATH}/services/ASC.Notify/service

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Notify/service/ .

CMD ["ASC.Notify.dll", "ASC.Notify", "core:eventBus:subscriptionClientName=asc_event_bus_notify_queue"]

## ASC.People ##
FROM dotnetrun AS people_server
WORKDIR ${BUILD_PATH}/products/ASC.People/server/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.People/service/ .

CMD ["ASC.People.dll", "ASC.People"]

## ASC.AI ##
FROM dotnetrun AS ai
WORKDIR ${BUILD_PATH}/products/ASC.AI/server/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.AI/service/ .

CMD ["ASC.AI.dll", "ASC.AI"]

## ASC.AI.Service ##
FROM dotnetrun AS ai_service
WORKDIR ${BUILD_PATH}/products/ASC.AI/service/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.AI.Service/service/ .

CMD ["ASC.AI.Service.dll", "ASC.AI.Service", "core:eventBus:subscriptionClientName=asc_event_bus_ai_service_queue"] 

## ASC.Socket.IO ##
FROM noderun AS socket
WORKDIR ${BUILD_PATH}/services/ASC.Socket.IO/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.Socket.IO .

CMD  ["server.js", "ASC.Socket.IO"]

## ASC.SsoAuth ##
FROM noderun AS ssoauth
WORKDIR ${BUILD_PATH}/services/ASC.SsoAuth/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-node --chown=onlyoffice:onlyoffice  ${SRC_PATH}/server/common/ASC.SsoAuth .

CMD ["app.js", "ASC.SsoAuth"]

## ASC.Studio.Notify ##
FROM dotnetrun AS studio_notify
WORKDIR ${BUILD_PATH}/services/ASC.Studio.Notify/service/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Studio.Notify/service/ .

CMD ["ASC.Studio.Notify.dll", "ASC.Studio.Notify"]

## ASC.Web.Api ##
FROM dotnetrun AS api
WORKDIR ${BUILD_PATH}/studio/ASC.Web.Api/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Web.Api/service/ .

CMD ["ASC.Web.Api.dll", "ASC.Web.Api"]

## ASC.Web.Studio ##
FROM dotnetrun AS studio
WORKDIR ${BUILD_PATH}/studio/ASC.Web.Studio/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-plugins --chown=onlyoffice:onlyoffice ${SRC_PATH}/plugins/publish/ ${BUILD_PATH}/studio/plugins
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Web.Studio/service/ .

CMD ["ASC.Web.Studio.dll", "ASC.Web.Studio", "core:eventBus:subscriptionClientName=asc_event_bus_webstudio_queue"]

## ASC.Web.HealthChecks.UI ##
FROM dotnetrun AS healthchecks
WORKDIR ${BUILD_PATH}/services/ASC.Web.HealthChecks.UI/service

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-healthchecks-entrypoint.sh ./docker-healthchecks-entrypoint.sh
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Web.HealthChecks.UI/service/ .

ENTRYPOINT ["./docker-healthchecks-entrypoint.sh"]
CMD ["ASC.Web.HealthChecks.UI.dll", "ASC.Web.HealthChecks.UI"]

## ASC.TelegramService ##
FROM dotnetrun AS telegram
WORKDIR ${BUILD_PATH}/services/ASC.TelegramService/service/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.TelegramService/service/ .

CMD ["ASC.TelegramService.dll", "ASC.TelegramService", "core:eventBus:subscriptionClientName=asc_event_bus_telegram_queue"]

## ASC.Migration.Runner ##
FROM dotnetrun AS onlyoffice-migration-runner
WORKDIR ${BUILD_PATH}/services/ASC.Migration.Runner/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-migration-entrypoint.sh ./docker-migration-entrypoint.sh
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Migration.Runner/service/ .

ENTRYPOINT ["./docker-migration-entrypoint.sh"]

## ASC.Identity.Authorization ##
FROM javarun AS identity-authorization
WORKDIR ${BUILD_PATH}/services/ASC.Identity.Authorization/
COPY --from=java-build --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Identity.Authorization/app.jar .
CMD ["ASC.Identity.Authorization"]

## ASC.Identity.Registration ##
FROM javarun AS identity-api
WORKDIR ${BUILD_PATH}/services/ASC.Identity.Registration/
COPY --from=java-build --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Identity.Registration/app.jar .
CMD ["ASC.Identity.Registration"]

## image for k8s bin-share ##
FROM busybox:latest AS bin_share
ARG SRC_PATH
RUN mkdir -p /app/ASC.Files/server && \
    mkdir -p /app/ASC.People/server && \
    mkdir -p /app/ASC.AI/server && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -u 104 onlyoffice --home /var/www/onlyoffice --system -G onlyoffice
USER onlyoffice
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/bin-share-docker-entrypoint.sh /app/docker-entrypoint.sh
COPY --from=files --chown=onlyoffice:onlyoffice /var/www/products/ASC.Files/server/ /app/ASC.Files/server/
COPY --from=people_server --chown=onlyoffice:onlyoffice /var/www/products/ASC.People/server/ /app/ASC.People/server/
COPY --from=ai --chown=onlyoffice:onlyoffice /var/www/products/ASC.AI/server/ /app/ASC.AI/server/
ENTRYPOINT ["./app/docker-entrypoint.sh"]

## image for k8s wait-bin-share ##
FROM busybox:latest AS wait_bin_share
ARG SRC_PATH
RUN addgroup --system --gid 107 onlyoffice && \
    adduser -u 104 onlyoffice --home /var/www/onlyoffice --system -G onlyoffice && \
    mkdir /app
USER onlyoffice
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/wait-bin-share-docker-entrypoint.sh /app/docker-entrypoint.sh
ENTRYPOINT ["./app/docker-entrypoint.sh"]

# Dotnet Services ##
FROM dotnetrun AS dotnet-services
ENV APP_STORAGE_ROOT=/app/onlyoffice/data/
ENV LOG_DIR=/var/log/onlyoffice
ENV PATH_TO_CONF=/app/onlyoffice/config

WORKDIR /usr/bin/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/supervisor/dotnet_services.conf /etc/supervisor/conf.d/supervisord.conf

COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.AI/service/ ${BUILD_PATH}/products/ASC.AI/server/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.AI.Service/service/ ${BUILD_PATH}/products/ASC.AI/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.ApiSystem/service/  ${BUILD_PATH}/services/ASC.ApiSystem/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.ClearEvents/service/  ${BUILD_PATH}/services/ASC.ClearEvents/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Data.Backup/service/ ${BUILD_PATH}/services/ASC.Data.Backup/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Data.Backup.BackgroundTasks/service/  ${BUILD_PATH}/services/ASC.Data.Backup.BackgroundTasks/service
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Files/service/ ${BUILD_PATH}/products/ASC.Files/server/

USER root
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Files.Service/service/ ${BUILD_PATH}/products/ASC.Files/service/
COPY --from=onlyoffice/ffvideo:7.1 --chown=onlyoffice:onlyoffice /app/src/ ${BUILD_PATH}/products/ASC.Files/service/

RUN set -eux; \
  ARCH=$(uname -m); \
  PKGS="libasound2t64 libv4l-0t64"; \
  [ "$ARCH" = "x86_64" ] && PKGS="$PKGS libdrm2 libplacebo-dev libxcb-shape0 ocl-icd-opencl-dev"; \
  apt-get update && apt-get install -y --no-install-recommends $PKGS && rm -rf /var/lib/apt/lists/* /tmp/*

USER onlyoffice

COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Migration.Runner/service/ ${BUILD_PATH}/services/ASC.Migration.Runner/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Notify/service/ ${BUILD_PATH}/services/ASC.Notify/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.People/service/ ${BUILD_PATH}/products/ASC.People/server/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Studio.Notify/service/ ${BUILD_PATH}/services/ASC.Studio.Notify/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.TelegramService/service/ ${BUILD_PATH}/services/ASC.TelegramService/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Web.Api/service/ ${BUILD_PATH}/services/ASC.Web.Api/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Web.HealthChecks.UI/service/ ${BUILD_PATH}/services/ASC.Web.HealthChecks.UI/service/
COPY --from=build-dotnet --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Web.Studio/service/ ${BUILD_PATH}/services/ASC.Web.Studio/service/
COPY --from=build-plugins --chown=onlyoffice:onlyoffice ${SRC_PATH}/plugins/publish/ ${BUILD_PATH}/studio/plugins

CMD ["supervisord", "-n"]

## Node Services ##
FROM noderun AS node-services
ENV APP_STORAGE_ROOT=/app/onlyoffice/data/
ENV LOG_DIR=/var/log/onlyoffice
ENV PATH_TO_CONF=/app/onlyoffice/config

WORKDIR /usr/bin/

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py ./docker-entrypoint.py
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/supervisor/node_services.conf /etc/supervisor/conf.d/supervisord.conf

COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/editor/ ${BUILD_PATH}/products/ASC.Editors/editor/
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/login/ ${BUILD_PATH}/products/ASC.Login/login/
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/management/ ${BUILD_PATH}/products/ASC.Management/management/
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/sdk/ ${BUILD_PATH}/products/ASC.Sdk/sdk/
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.Socket.IO ${BUILD_PATH}/services/ASC.Socket.IO/
COPY --from=build-node --chown=onlyoffice:onlyoffice ${SRC_PATH}/server/common/ASC.SsoAuth ${BUILD_PATH}/services/ASC.SsoAuth/

CMD ["supervisord", "-n"]

## Java Services ##
FROM javarun AS java-services
ENV LOG_DIR=/var/log/onlyoffice

COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-identity-entrypoint.sh /usr/bin/docker-identity-entrypoint.sh
COPY --from=src --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/supervisor/java_services.conf /etc/supervisor/conf.d/supervisord.conf

COPY --from=java-build --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Identity.Authorization/app.jar ${BUILD_PATH}/services/ASC.Identity.Authorization/app.jar
COPY --from=java-build --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/services/ASC.Identity.Registration/app.jar ${BUILD_PATH}/services/ASC.Identity.Registration/app.jar

ENTRYPOINT ["/usr/bin/supervisord", "-n"]
