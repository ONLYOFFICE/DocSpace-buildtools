ARG SRC_PATH="/app/onlyoffice/src"
ARG BUILD_PATH="/var/www"
ARG DOTNET_SDK="mcr.microsoft.com/dotnet/sdk:8.0"
ARG DOTNET_RUN="mcr.microsoft.com/dotnet/aspnet:8.0"

FROM $DOTNET_SDK AS base
ARG RELEASE_DATE="2016-06-22"
ARG DEBIAN_FRONTEND=noninteractive
ARG PRODUCT_VERSION=0.0.0
ARG BUILD_NUMBER=0
ARG GIT_BRANCH="master"
ARG SRC_PATH
ARG BUILD_PATH
ARG BUILD_ARGS="build"
ARG DEPLOY_ARGS="deploy"
ARG DEBUG_INFO="true"
ARG PUBLISH_CNF="Release"

LABEL onlyoffice.appserver.release-date="${RELEASE_DATE}" \
    maintainer="Ascensio System SIA <support@onlyoffice.com>"

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN apt-get -y update && \
    apt-get install -yq \
    sudo \
    locales \
    git \
    python3-pip \
    maven \
    npm  && \
    locale-gen en_US.UTF-8 && \
    npm install --global yarn && \
    wget -O openjdk-21-jdk.deb https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.deb && \
    dpkg -i openjdk-21-jdk.deb && apt-get install -f && \
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/nodesource.gpg --import && \
    chmod 644 /usr/share/keyrings/nodesource.gpg && \
    apt-get -y update && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

ADD https://api.github.com/repos/ONLYOFFICE/DocSpace-buildtools/git/refs/heads/${GIT_BRANCH} version.json
RUN git clone -b ${GIT_BRANCH} https://github.com/ONLYOFFICE/DocSpace-buildtools.git ${SRC_PATH}/buildtools && \
    git clone --recurse-submodules -b ${GIT_BRANCH} https://github.com/ONLYOFFICE/DocSpace-Server.git ${SRC_PATH}/server && \
    git clone -b ${GIT_BRANCH} https://github.com/ONLYOFFICE/DocSpace-Client.git ${SRC_PATH}/client && \
    git clone -b "master" --depth 1 https://github.com/ONLYOFFICE/ASC.Web.Campaigns.git ${SRC_PATH}/campaigns

RUN cd ${SRC_PATH} && \
    mkdir -p /app/onlyoffice/config/ && \
    cd buildtools/config && \
    ls | grep -v test | grep -v dev | grep -v nginx | xargs cp -t /app/onlyoffice/config/ && \
    cd ${SRC_PATH} && \
    cp buildtools/config/*.config /app/onlyoffice/config/ && \
    mkdir -p /etc/nginx/conf.d && cp -f buildtools/config/nginx/onlyoffice*.conf /etc/nginx/conf.d/ && \
    mkdir -p /etc/nginx/includes/ && cp -f buildtools/config/nginx/includes/onlyoffice*.conf /etc/nginx/includes/ && cp -f buildtools/config/nginx/includes/server-*.conf /etc/nginx/includes/ && \
    sed -i "s/\"number\".*,/\"number\": \"${PRODUCT_VERSION}.${BUILD_NUMBER}\",/g" /app/onlyoffice/config/appsettings.json && \
    sed -e 's/#//' -i /etc/nginx/conf.d/onlyoffice.conf && \
    cd ${SRC_PATH}/buildtools/install/common/ && \
    bash build-frontend.sh -sp "${SRC_PATH}" -ba "${BUILD_ARGS}" -da "${DEPLOY_ARGS}" -di "${DEBUG_INFO}" && \
    bash build-backend.sh -sp "${SRC_PATH}"  && \
    bash publish-backend.sh -pc "${PUBLISH_CNF}" -sp "${SRC_PATH}/server" -bp "${BUILD_PATH}"  && \
    cp -rf ${SRC_PATH}/server/products/ASC.Files/Server/DocStore ${BUILD_PATH}/products/ASC.Files/server/ && \
    rm -rf ${SRC_PATH}/server/common/* && \
    rm -rf ${SRC_PATH}/server/web/ASC.Web.Core/* && \
    rm -rf ${SRC_PATH}/server/web/ASC.Web.Studio/* && \
    rm -rf ${SRC_PATH}/server/products/ASC.Files/Server/* && \
    rm -rf ${SRC_PATH}/server/products/ASC.Files/Service/* && \
    rm -rf ${SRC_PATH}/server/products/ASC.People/Server/* 

COPY --chown=onlyoffice:onlyoffice config/mysql/conf.d/mysql.cnf /etc/mysql/conf.d/mysql.cnf

FROM $DOTNET_RUN AS dotnetrun
ARG BUILD_PATH
ARG SRC_PATH
ENV BUILD_PATH=${BUILD_PATH}
ENV SRC_PATH=${SRC_PATH}

# add defualt user and group for no-root run
RUN mkdir -p /var/log/onlyoffice && \
    mkdir -p /app/onlyoffice/data && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -uid 104 --quiet --home /var/www/onlyoffice --system --gid 107 onlyoffice && \
    chown onlyoffice:onlyoffice /app/onlyoffice -R && \
    chown onlyoffice:onlyoffice /var/log -R && \
    chown onlyoffice:onlyoffice /var/www -R && \
    apt-get -y update && \
    apt-get install -yq \
    sudo \
    nano \
    curl \
    vim \
    python3-pip \
    libgdiplus && \
    pip3 install --upgrade --break-system-packages jsonpath-ng multipledispatch netaddr netifaces && \
    rm -rf /var/lib/apt/lists/*

COPY --from=base --chown=onlyoffice:onlyoffice /app/onlyoffice/config/* /app/onlyoffice/config/

USER onlyoffice
EXPOSE 5050
ENTRYPOINT ["python3", "docker-entrypoint.py"]

FROM node:20-slim AS noderun
ARG BUILD_PATH
ARG SRC_PATH 
ENV BUILD_PATH=${BUILD_PATH}
ENV SRC_PATH=${SRC_PATH}

RUN mkdir -p /var/log/onlyoffice && \
    mkdir -p /app/onlyoffice/data && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -uid 104 --quiet --home /var/www/onlyoffice --system --gid 107 onlyoffice && \
    chown onlyoffice:onlyoffice /app/onlyoffice -R && \
    chown onlyoffice:onlyoffice /var/log -R  && \
    chown onlyoffice:onlyoffice /var/www -R && \
    apt-get -y update && \
    apt-get install -yq \ 
    sudo \
    nano \
    curl \
    vim \
    python3-pip && \
    pip3 install --upgrade --break-system-packages jsonpath-ng multipledispatch netaddr netifaces && \
    rm -rf /var/lib/apt/lists/*

COPY --from=base --chown=onlyoffice:onlyoffice /app/onlyoffice/config/* /app/onlyoffice/config/
USER onlyoffice
EXPOSE 5050
ENTRYPOINT ["python3", "docker-entrypoint.py"]

FROM eclipse-temurin:21-jre-alpine AS javarun
ARG BUILD_PATH
ENV BUILD_PATH=${BUILD_PATH}

RUN mkdir -p /var/log/onlyoffice && \
    mkdir -p /var/www/onlyoffice && \
    addgroup -S -g 107 onlyoffice && \
    adduser -S -u 104 -h /var/www/onlyoffice -G onlyoffice onlyoffice && \
    chown onlyoffice:onlyoffice /var/log -R  && \
    chown onlyoffice:onlyoffice /var/www -R && \
    apk add --no-cache sudo bash nano curl 

COPY ./docker-identity-entrypoint.sh /usr/bin/docker-identity-entrypoint.sh
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

RUN apt-get -y update && \
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
COPY --from=base --chown=onlyoffice:onlyoffice /etc/nginx/conf.d /etc/nginx/conf.d
COPY --from=base --chown=onlyoffice:onlyoffice /etc/nginx/includes /etc/nginx/includes
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/client ${BUILD_PATH}/client
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/public ${BUILD_PATH}/public
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/campaigns/src/campaigns ${BUILD_PATH}/public/campaigns
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/management ${BUILD_PATH}/management
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/docker-entrypoint.d /docker-entrypoint.d
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/templates/upstream.conf.template /etc/nginx/templates/upstream.conf.template
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/templates/nginx.conf.template /etc/nginx/nginx.conf.template
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/config/nginx/html /etc/nginx/html
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/prepare-nginx-router.sh /docker-entrypoint.d/prepare-nginx-router.sh
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/config/nginx/docker-entrypoint.sh /docker-entrypoint.sh

USER onlyoffice

# changes for upstream configure
RUN sed -i 's/127.0.0.1:5010/$service_api_system/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5012/$service_backup/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5007/$service_files/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5004/$service_people_server/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5000/$service_api/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5003/$service_studio/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9899/$service_socket/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9834/$service_sso/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5013/$service_doceditor/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5011/$service_login/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9090/$service_identity_api/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:8080/$service_identity/' /etc/nginx/conf.d/onlyoffice.conf && \
    if [[ -z "${SERVICE_CLIENT}" ]] ; then sed -i 's/127.0.0.1:5001/$service_client/' /etc/nginx/conf.d/onlyoffice.conf; fi && \
    if [[ -z "${SERVICE_MANAGEMENT}" ]] ; then sed -i 's/127.0.0.1:5015/$service_management/' /etc/nginx/conf.d/onlyoffice.conf; fi && \
    sed -i 's/127.0.0.1:5033/$service_healthchecks/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5601/$dashboards_host:5601/' /etc/nginx/includes/server-dashboards.conf && \
    sed -i 's/$public_root/\/var\/www\/public\//' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/http:\/\/172.*/$document_server;/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i '/client_body_temp_path/ i \ \ \ \ $MAP_HASH_BUCKET_SIZE' /etc/nginx/nginx.conf.template && \
    sed -i 's/\(worker_connections\).*;/\1 $COUNT_WORKER_CONNECTIONS;/' /etc/nginx/nginx.conf.template && \
    sed -i -e '/^user/s/^/#/' -e 's#/tmp/nginx.pid#nginx.pid#' -e 's#/etc/nginx/mime.types#mime.types#' /etc/nginx/nginx.conf.template 

ENTRYPOINT  [ "/docker-entrypoint.sh" ]

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]

## Doceditor ##
FROM noderun AS doceditor
WORKDIR ${BUILD_PATH}/products/ASC.Editors/editor

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/editor/ .

CMD ["server.js", "ASC.Editors"]

## Login ##
FROM noderun AS login
WORKDIR ${BUILD_PATH}/products/ASC.Login/login

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/publish/web/login/ .

CMD ["server.js", "ASC.Login"]

## ASC.Data.Backup.BackgroundTasks ##
FROM dotnetrun AS backup_background
WORKDIR ${BUILD_PATH}/services/ASC.Data.Backup.BackgroundTasks/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Data.Backup.BackgroundTasks/service/  .

CMD ["ASC.Data.Backup.BackgroundTasks.dll", "ASC.Data.Backup.BackgroundTasks", "core:eventBus:subscriptionClientName=asc_event_bus_backup_queue"]

# ASC.ApiSystem ##
FROM dotnetrun AS api_system
WORKDIR ${BUILD_PATH}/services/ASC.ApiSystem/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.ApiSystem/service/  .

CMD ["ASC.ApiSystem.dll", "ASC.ApiSystem"]

## ASC.ClearEvents ##
FROM dotnetrun AS clear-events
WORKDIR ${BUILD_PATH}/services/ASC.ClearEvents/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.ClearEvents/service/  .

CMD ["ASC.ClearEvents.dll", "ASC.ClearEvents"]

## ASC.Data.Backup ##
FROM dotnetrun AS backup
WORKDIR ${BUILD_PATH}/services/ASC.Data.Backup/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Data.Backup/service/ .

CMD ["ASC.Data.Backup.dll", "ASC.Data.Backup"]

## ASC.Files ##
FROM dotnetrun AS files
WORKDIR ${BUILD_PATH}/products/ASC.Files/server/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/products/ASC.Files/server/ .

CMD ["ASC.Files.dll", "ASC.Files"]

## ASC.Files.Service ##
FROM dotnetrun AS files_services
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
WORKDIR ${BUILD_PATH}/products/ASC.Files/service/
USER root
RUN  echo "deb http://security.ubuntu.com/ubuntu focal-security main" | tee /etc/apt/sources.list && \
    apt-key adv --keyserver keys.gnupg.net --recv-keys 3B4FE6ACC0B21F32 && \
    apt-key adv --keyserver keys.gnupg.net --recv-keys 871920D1991BC93C && \
    apt-get -y update && \
    apt-get install -yq libssl1.1 && \
    rm -rf /var/lib/apt/lists/*
USER onlyoffice
COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Files.Service/service/ .
COPY --from=onlyoffice/ffvideo:6.0 --chown=onlyoffice:onlyoffice /usr/local /usr/local/

CMD ["ASC.Files.Service.dll", "ASC.Files.Service", "core:eventBus:subscriptionClientName=asc_event_bus_files_service_queue"]

## ASC.Notify ##
FROM dotnetrun AS notify
WORKDIR ${BUILD_PATH}/services/ASC.Notify/service

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Notify/service/ .

CMD ["ASC.Notify.dll", "ASC.Notify", "core:eventBus:subscriptionClientName=asc_event_bus_notify_queue"]

## ASC.People ##
FROM dotnetrun AS people_server
WORKDIR ${BUILD_PATH}/products/ASC.People/server/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/products/ASC.People/server/ .

CMD ["ASC.People.dll", "ASC.People"]

## ASC.Socket.IO ##
FROM noderun AS socket
WORKDIR ${BUILD_PATH}/services/ASC.Socket.IO/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Socket.IO/service/ .

CMD  ["server.js", "ASC.Socket.IO"]

## ASC.SsoAuth ##
FROM noderun AS ssoauth
WORKDIR ${BUILD_PATH}/services/ASC.SsoAuth/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice  ${BUILD_PATH}/services/ASC.SsoAuth/service/ .

CMD ["app.js", "ASC.SsoAuth"]

## ASC.Studio.Notify ##
FROM dotnetrun AS studio_notify
WORKDIR ${BUILD_PATH}/services/ASC.Studio.Notify/service/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Studio.Notify/service/ .

CMD ["ASC.Studio.Notify.dll", "ASC.Studio.Notify"]

## ASC.Web.Api ##
FROM dotnetrun AS api
WORKDIR ${BUILD_PATH}/studio/ASC.Web.Api/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Web.Api/service/ .

CMD ["ASC.Web.Api.dll", "ASC.Web.Api"]

## ASC.Web.Studio ##
FROM dotnetrun AS studio
WORKDIR ${BUILD_PATH}/studio/ASC.Web.Studio/

COPY --chown=onlyoffice:onlyoffice docker-entrypoint.py ./docker-entrypoint.py
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Web.Studio/service/ .

CMD ["ASC.Web.Studio.dll", "ASC.Web.Studio", "core:eventBus:subscriptionClientName=asc_event_bus_webstudio_queue"]

## ASC.Web.HealthChecks.UI ##
FROM dotnetrun AS healthchecks
WORKDIR ${BUILD_PATH}/services/ASC.Web.HealthChecks.UI/service

COPY --chown=onlyoffice:onlyoffice docker-healthchecks-entrypoint.sh ./docker-healthchecks-entrypoint.sh
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Web.HealthChecks.UI/service/ .

ENTRYPOINT ["./docker-healthchecks-entrypoint.sh"]
CMD ["ASC.Web.HealthChecks.UI.dll", "ASC.Web.HealthChecks.UI"]

## ASC.Migration.Runner ##
FROM $DOTNET_RUN AS onlyoffice-migration-runner
ARG BUILD_PATH
ARG SRC_PATH 
ENV BUILD_PATH=${BUILD_PATH}
ENV SRC_PATH=${SRC_PATH}
RUN addgroup --system --gid 107 onlyoffice && \
    adduser -uid 104 --quiet --home /var/www/onlyoffice --system --gid 107 onlyoffice
USER onlyoffice
WORKDIR ${BUILD_PATH}/services/ASC.Migration.Runner/
COPY  ./docker-migration-entrypoint.sh ./docker-migration-entrypoint.sh
COPY --from=base ${SRC_PATH}/server/ASC.Migration.Runner/service/ .

ENTRYPOINT ["./docker-migration-entrypoint.sh"]

## ASC.Identity.Authorization ##
FROM javarun AS identity-authorization
WORKDIR ${BUILD_PATH}/services/ASC.Identity.Authorization/
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Identity.Authorization/service/ .
CMD ["ASC.Identity.Authorization"]

## ASC.Identity.Registration ##
FROM javarun AS identity-api
WORKDIR ${BUILD_PATH}/services/ASC.Identity.Registration/
COPY --from=base --chown=onlyoffice:onlyoffice  ${BUILD_PATH}/services/ASC.Identity.Registration/service/ .
CMD ["ASC.Identity.Registration"]

## ASC.Identity.Migration ##
FROM javarun AS identity-migration
WORKDIR ${BUILD_PATH}/services/ASC.Identity.Migration/
COPY --from=base --chown=onlyoffice:onlyoffice  ${BUILD_PATH}/services/ASC.Identity.Migration/service/ .
CMD ["ASC.Identity.Migration"]

## image for k8s bin-share ##
FROM busybox:latest AS bin_share
RUN mkdir -p /app/ASC.Files/server && \
    mkdir -p /app/ASC.People/server && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -u 104 onlyoffice --home /var/www/onlyoffice --system -G onlyoffice
USER onlyoffice
COPY --chown=onlyoffice:onlyoffice bin-share-docker-entrypoint.sh /app/docker-entrypoint.sh
COPY --from=base --chown=onlyoffice:onlyoffice /var/www/products/ASC.Files/server/ /app/ASC.Files/server/
COPY --from=base --chown=onlyoffice:onlyoffice /var/www/products/ASC.People/server/ /app/ASC.People/server/
ENTRYPOINT ["./app/docker-entrypoint.sh"]

## image for k8s wait-bin-share ##
FROM busybox:latest AS wait_bin_share
RUN addgroup --system --gid 107 onlyoffice && \
    adduser -u 104 onlyoffice --home /var/www/onlyoffice --system -G onlyoffice && \
    mkdir /app
USER onlyoffice
COPY --chown=onlyoffice:onlyoffice wait-bin-share-docker-entrypoint.sh /app/docker-entrypoint.sh
ENTRYPOINT ["./app/docker-entrypoint.sh"]
