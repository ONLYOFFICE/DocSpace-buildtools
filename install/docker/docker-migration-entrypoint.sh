#!/bin/bash

MYSQL_HOST=${MYSQL_HOST:-${MYSQL_CONTAINER_NAME}}
MYSQL_PORT=${MYSQL_PORT:-"3306"}
MYSQL_DATABASE=${MYSQL_DATABASE:-"onlyoffice"}
MYSQL_USER=${MYSQL_USER:-"onlyoffice_user"}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-"onlyoffice_pass"}
MIGRATION_TYPE=${MIGRATION_TYPE:-"STANDALONE"}
PARAMETERS="standalone=true"

sed -i "s!\"ConnectionString\".*!\"ConnectionString\": \"Server=${MYSQL_HOST};Port=${MYSQL_PORT};Database=${MYSQL_DATABASE};User ID=${MYSQL_USER};Password=${MYSQL_PASSWORD}\",!g" ./appsettings.runner.json

if [[ ${MIGRATION_TYPE} == "SAAS" ]]
then
    PARAMETERS=""
fi

dotnet ASC.Migration.Runner.dll ${PARAMETERS}
