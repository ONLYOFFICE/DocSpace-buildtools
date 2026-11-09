#!/bin/bash

source /usr/bin/entrypoint-functions.sh

MYSQL_HOST=${MYSQL_HOST:-${MYSQL_CONTAINER_NAME}}
MYSQL_PORT=${MYSQL_PORT:-"3306"}
MYSQL_DATABASE=${MYSQL_DATABASE:-"onlyoffice"}
MYSQL_USER=${MYSQL_USER:-"onlyoffice_user"}
MYSQL_PASSWORD=${MYSQL_PASSWORD:?MYSQL_PASSWORD must be set}
COMMAND_TIMEOUT=${COMMAND_TIMEOUT:-"200"}
MIGRATION_TYPE=${MIGRATION_TYPE:-"STANDALONE"}
PARAMETERS="standalone=true"

# Escape the value for a JSON string that is written through sed with "!" as the delimiter
CONNECTION_STRING="Server=${MYSQL_HOST};Port=${MYSQL_PORT};Database=${MYSQL_DATABASE};User ID=$(quote_connection_value "${MYSQL_USER}");Password=$(quote_connection_value "${MYSQL_PASSWORD}");Command Timeout=${COMMAND_TIMEOUT}"
CONNECTION_STRING_ESCAPED=$(printf '%s' "$CONNECTION_STRING" | sed -e 's/[\\"]/\\&/g' -e 's/[\\&!]/\\&/g')
sed -i "s!\"ConnectionString\".*!\"ConnectionString\": \"${CONNECTION_STRING_ESCAPED}\"!g" ./appsettings.runner.json

if [[ ${MIGRATION_TYPE} == "SAAS" ]]
then
    PARAMETERS=""
fi

exec dotnet ASC.Migration.Runner.dll ${PARAMETERS}
