ARG SRC_PATH="/app/onlyoffice/src"
ARG BUILD_PATH="/var/www"
ARG DOTNET_SDK="mcr.microsoft.com/dotnet/sdk:7.0"
ARG DOTNET_RUN="mcr.microsoft.com/dotnet/aspnet:7.0"

FROM $DOTNET_SDK AS base
ARG SRC_PATH
ARG BUILD_PATH
ARG BUILD_DOTNET_CORE_ARGS
ENV BUILD_DOTNET_CORE_ARGS=${BUILD_DOTNET_CORE_ARGS}
ARG PROPERTY_BUILD="all"
ARG BACKEND_NODEJS_SERVICES
ENV BACKEND_NODEJS_SERVICES=${BACKEND_NODEJS_SERVICES}
ARG BACKEND_DOTNETCORE_SERVICES
ENV BACKEND_DOTNETCORE_SERVICES=${BACKEND_DOTNETCORE_SERVICES}
ARG SELF_CONTAINED=""
ARG PUBLISH_BACKEND_ARGS
ENV PUBLISH_BACKEND_ARGS=${PUBLISH_BACKEND_ARGS}
ARG PUBLISH_CNF="Release"
ARG FRONTEND_BUILD_ARGS="build"
ARG FRONTEND_DEPLOY_ARGS="deploy"
ARG DEBUG_INFO_CHECK="true"
ARG MIGRATION_CHECK="true"
ARG GIT_BRANCH="master"
ARG RELEASE_DATE="2016-06-22"
ARG DEBIAN_FRONTEND=noninteractive
ARG PRODUCT_VERSION=0.0.0
ARG BUILD_NUMBER=0

LABEL onlyoffice.appserver.release-date="${RELEASE_DATE}" \
    maintainer="Ascensio System SIA <support@onlyoffice.com>"

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

WORKDIR ${SRC_PATH}

COPY . .

RUN apt-get -y update && \
    apt-get install -yq \
    sudo \
    locales \
    git \
    npm  && \
    locale-gen en_US.UTF-8 && \
    npm install --global yarn && \
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/nodesource.gpg --import && \
    chmod 644 /usr/share/keyrings/nodesource.gpg && \
    apt-get -y update && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*
RUN git clone -b main/community-server https://github.com/ONLYOFFICE/document-templates ${SRC_PATH}/ASC.Files/Server/DocStore

RUN mkdir -p /app/onlyoffice/ && \
    find config/ -maxdepth 1 -name "*.json" | grep -v test | grep -v dev | xargs tar -cvf config.tar && \
    tar -C "/app/onlyoffice/" -xvf config.tar && \
    cp config/*.config /app/onlyoffice/config/ && \
    mkdir -p ${SRC_PATH}/buildtools/deploy/client && \
    mkdir -p ${SRC_PATH}/buildtools/deploy/public && \
    mkdir -p /etc/nginx/conf.d && cp -f config/nginx/onlyoffice*.conf /etc/nginx/conf.d/ && \
    mkdir -p /etc/nginx/includes/ && cp -f config/nginx/includes/onlyoffice*.conf /etc/nginx/includes/ && \
    sed -i "s/\"number\".*,/\"number\": \"${PRODUCT_VERSION}.${BUILD_NUMBER}\",/g" /app/onlyoffice/config/appsettings.json && \
    sed -e 's/#//' -i /etc/nginx/conf.d/onlyoffice.conf && \
    cd ${SRC_PATH}/buildtools/install/common/ && \
    bash build-services.sh \
    -sp "${SRC_PATH}" \
    -bp "${BUILD_PATH}" \
    -pb "${PROPERTY_BUILD}" \
    -sc "${SELF_CONTAINED}" \
    -pc "${PUBLISH_CNF}" \
    -yb "${FRONTEND_BUILD_ARGS}" \
    -yd "${FRONTEND_DEPLOY_ARGS}" \
    -dc "${DEBUG_INFO_CHECK}" \
    -mc "${MIGRATION_CHECK}" &&\
    rm -rf ${SRC_PATH}/common/* && \
    rm -rf ${SRC_PATH}/web/ASC.Web.Core/* && \
    rm -rf ${SRC_PATH}/web/ASC.Web.Studio/* && \
    rm -rf ${SRC_PATH}/products/ASC.Files/Service/* && \
    rm -rf ${SRC_PATH}/products/ASC.Files/Server/* && \
    rm -rf ${SRC_PATH}/products/ASC.People/Server/* 

FROM $DOTNET_RUN as dotnetrun
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
    python3-pip \
    nano \
    curl \
    vim \
    libgdiplus && \
    pip3 install --upgrade jsonpath-ng multipledispatch netaddr netifaces && \
    rm -rf /var/lib/apt/lists/*

COPY --from=base --chown=onlyoffice:onlyoffice /app/onlyoffice/config/* /app/onlyoffice/config/

#USER onlyoffice
EXPOSE 5050
ENTRYPOINT ["python3", "docker-entrypoint.py"]

FROM node:20.11.0-slim as noderun
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
    nano \
    curl \
    vim \
    python3-pip && \
    pip3 install --upgrade jsonpath-ng multipledispatch netaddr netifaces --break-system-packages && \
    rm -rf /var/lib/apt/lists/*

COPY --from=base --chown=onlyoffice:onlyoffice /app/onlyoffice/config/* /app/onlyoffice/config/

EXPOSE 5050
ENTRYPOINT ["python3", "docker-entrypoint.py"]

## Nginx image ##
FROM nginx AS router
ARG SRC_PATH
ARG BUILD_PATH
ARG COUNT_WORKER_CONNECTIONS=1024
ENV DNS_NAMESERVER=127.0.0.11 \
    COUNT_WORKER_CONNECTIONS=$COUNT_WORKER_CONNECTIONS \
    MAP_HASH_BUCKET_SIZE=""

RUN apt-get -y update && \
    apt-get install -yq vim && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /usr/share/nginx/html/* 

# copy static services files and config values 
COPY --from=base /etc/nginx/conf.d /etc/nginx/conf.d
COPY --from=base /etc/nginx/includes /etc/nginx/includes
COPY --from=base ${SRC_PATH}/buildtools/deploy/client ${BUILD_PATH}/client
COPY --from=base ${SRC_PATH}/buildtools/deploy/public ${BUILD_PATH}/public
COPY --from=base ${SRC_PATH}/buildtools/install/docker/config/nginx/templates/upstream.conf.template /etc/nginx/templates/upstream.conf.template
COPY --from=base ${SRC_PATH}/buildtools/install/docker/config/nginx/templates/nginx.conf.template /etc/nginx/nginx.conf.template
COPY --from=base ${SRC_PATH}/buildtools/install/docker/prepare-nginx-router.sh /docker-entrypoint.d/prepare-nginx-router.sh

# add defualt user and group for no-root run
RUN chown nginx:nginx /etc/nginx/* -R && \
    chown nginx:nginx /docker-entrypoint.d/* && \
    # changes for upstream configure
    sed -i 's/127.0.0.1:5010/$service_api_system/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5012/$service_backup/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5007/$service_files/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5004/$service_people_server/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5000/$service_api/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5003/$service_studio/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9899/$service_socket/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9834/$service_sso/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5013/$service_doceditor/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5099/$service_sdk/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:5011/$service_login/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:9090/$service_identity_api/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/127.0.0.1:8080/$service_identity/' /etc/nginx/conf.d/onlyoffice.conf && \
    if [[ -z "${SERVICE_CLIENT}" ]] ; then sed -i 's/127.0.0.1:5001/$service_client/' /etc/nginx/conf.d/onlyoffice.conf; fi && \
    if [[ -z "${SERVICE_MANAGEMENT}" ]] ; then sed -i 's/127.0.0.1:5015/$service_management/' /etc/nginx/conf.d/onlyoffice.conf; fi && \
    sed -i 's/127.0.0.1:5033/$service_healthchecks/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/$public_root/\/var\/www\/public\//' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i 's/172.*/$document_server;/' /etc/nginx/conf.d/onlyoffice.conf && \
    sed -i '/client_body_temp_path/ i \ \ \ \ $MAP_HASH_BUCKET_SIZE' /etc/nginx/nginx.conf.template && \
    sed -i 's/\(worker_connections\).*;/\1 $COUNT_WORKER_CONNECTIONS;/' /etc/nginx/nginx.conf.template 


## Sdk ##
FROM noderun AS sdk
WORKDIR ${BUILD_PATH}/products/ASC.Sdk/sdk

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/deploy/sdk/ .

CMD ["server.js", "ASC.Sdk"]

## Doceditor ##
FROM noderun as doceditor
WORKDIR ${BUILD_PATH}/services/ASC.Editors/editor

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/deploy/editor/ .

CMD ["server.js", "ASC.Editors"]

## Login ##
FROM noderun as login
WORKDIR ${BUILD_PATH}/services/ASC.Login/login

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/deploy/login/ .

CMD ["server.js", "ASC.Login"]

## ASC.Data.Backup.BackgroundTasks ##
FROM dotnetrun AS backup_background
WORKDIR ${BUILD_PATH}/services/ASC.Data.Backup.BackgroundTasks/service/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Data.Backup.BackgroundTasks/service/  .

CMD ["ASC.Data.Backup.BackgroundTasks.dll", "ASC.Data.Backup.BackgroundTasks", "core:eventBus:subscriptionClientName=asc_event_bus_backup_queue"]

# ASC.ApiSystem ##
FROM dotnetrun AS api_system
WORKDIR ${BUILD_PATH}/services/ASC.ApiSystem/service/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.ApiSystem/service/  .

CMD ["ASC.ApiSystem.dll", "ASC.ApiSystem"]

## ASC.ClearEvents ##
FROM dotnetrun AS clear-events
WORKDIR ${BUILD_PATH}/services/ASC.ClearEvents/service/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.ClearEvents/service/  .

CMD ["ASC.ClearEvents.dll", "ASC.ClearEvents"]

## ASC.Data.Backup ##
FROM dotnetrun AS backup
WORKDIR ${BUILD_PATH}/services/ASC.Data.Backup/service/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Data.Backup/service/ .

CMD ["ASC.Data.Backup.dll", "ASC.Data.Backup"]

## ASC.Files ##
FROM dotnetrun AS files
WORKDIR ${BUILD_PATH}/products/ASC.Files/server/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Files/service/ .
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/ASC.Files/Server/DocStore .

CMD ["ASC.Files.dll", "ASC.Files"]

## ASC.Files.Service ##
FROM dotnetrun AS files_services
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64
WORKDIR ${BUILD_PATH}/products/ASC.Files/service/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Files.Service/service/ .
COPY --from=linuxserver/ffmpeg:latest --chown=onlyoffice:onlyoffice /usr/local/bin/ /usr/local/bin/

CMD ["ASC.Files.Service.dll", "ASC.Files.Service", "core:eventBus:subscriptionClientName=asc_event_bus_files_service_queue"]

## ASC.Notify ##
FROM dotnetrun AS notify
WORKDIR ${BUILD_PATH}/services/ASC.Notify/service/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Notify/service/ .

CMD ["ASC.Notify.dll", "ASC.Notify", "core:eventBus:subscriptionClientName=asc_event_bus_notify_queue"]

## ASC.People ##
FROM dotnetrun AS people_server
WORKDIR ${BUILD_PATH}/products/ASC.People/server/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.People/service/ .

CMD ["ASC.People.dll", "ASC.People"]

## ASC.Socket.IO ##
FROM noderun AS socket
WORKDIR ${BUILD_PATH}/services/ASC.Socket.IO/service/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Socket.IO/service/ .

CMD  ["server.js", "ASC.Socket.IO"]

## ASC.SsoAuth ##
FROM noderun AS ssoauth
WORKDIR ${BUILD_PATH}/services/ASC.SsoAuth/service/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice  ${BUILD_PATH}/services/ASC.SsoAuth/service/ .

CMD ["app.js", "ASC.SsoAuth"]

## ASC.Studio.Notify ##
FROM dotnetrun AS studio_notify
WORKDIR ${BUILD_PATH}/services/ASC.Studio.Notify/service/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Studio.Notify/service/ .

CMD ["ASC.Studio.Notify.dll", "ASC.Studio.Notify"]

## ASC.Web.Api ##
FROM dotnetrun AS api
WORKDIR ${BUILD_PATH}/studio/ASC.Web.Api/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Web.Api/service/ .

CMD ["ASC.Web.Api.dll", "ASC.Web.Api"]

## ASC.Web.Studio ##
FROM dotnetrun AS studio
WORKDIR ${BUILD_PATH}/studio/ASC.Web.Studio/

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-entrypoint.py .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Web.Studio/service/ .

CMD ["ASC.Web.Studio.dll", "ASC.Web.Studio"]

## ASC.Web.HealthChecks.UI ##
FROM dotnetrun AS healthchecks
WORKDIR ${BUILD_PATH}/services/ASC.Web.HealthChecks.UI/service

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-healthchecks-entrypoint.sh .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Web.HealthChecks.UI/service/ .

ENTRYPOINT ["./docker-healthchecks-entrypoint.sh"]
CMD ["ASC.Web.HealthChecks.UI.dll", "ASC.Web.HealthChecks.UI"]

## ASC.Migration.Runner ##
FROM $DOTNET_RUN AS onlyoffice-migration-runner
ARG BUILD_PATH
ARG SRC_PATH 
ENV BUILD_PATH=${BUILD_PATH}
ENV SRC_PATH=${SRC_PATH}
WORKDIR ${BUILD_PATH}/services/ASC.Migration.Runner/
COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/docker-migration-entrypoint.sh .
COPY --from=base --chown=onlyoffice:onlyoffice ${BUILD_PATH}/services/ASC.Migration.Runner/service/ .

ENTRYPOINT ["./docker-migration-entrypoint.sh"]

## image for k8s bin-share ##
FROM busybox:latest AS bin_share
ARG BUILD_PATH
ARG SRC_PATH
ENV BUILD_PATH=${BUILD_PATH}
ENV SRC_PATH=${SRC_PATH}

RUN mkdir -p /app/ASC.Files/server && \
    mkdir -p /app/ASC.People/server && \
    addgroup --system --gid 107 onlyoffice && \
    adduser -u 104 onlyoffice --home /var/www/onlyoffice --system -G onlyoffice

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/bin-share-docker-entrypoint.sh /app/docker-entrypoint.sh
COPY --from=base /var/www/services/ASC.Files/service/ /app/ASC.Files/server/
COPY --from=base /var/www/services/ASC.People/service/ /app/ASC.People/server/
ENTRYPOINT ["./app/docker-entrypoint.sh"]

## image for k8s wait-bin-share ##
FROM busybox:latest AS wait_bin_share
ARG BUILD_PATH
ARG SRC_PATH
ENV BUILD_PATH=${BUILD_PATH}
ENV SRC_PATH=${SRC_PATH}

RUN mkdir /app

COPY --from=base --chown=onlyoffice:onlyoffice ${SRC_PATH}/buildtools/install/docker/wait-bin-share-docker-entrypoint.sh /app/docker-entrypoint.sh
ENTRYPOINT ["./app/docker-entrypoint.sh"]
