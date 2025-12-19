#!/bin/bash 
# read parameters
if [ -n "$1" ]; then
	RUN_DLL="${1}";
	shift
fi

if [ -n "$1" ]; then
	NAME_SERVICE="${1}";
	shift
fi

echo "Executing -- ${NAME_SERVICE}"

PRODUCT=${PRODUCT:-"onlyoffice"}
CONTAINER_PREFIX=${PRODUCT}-
SERVICE_PORT=${SERVICE_PORT:-"5050"}
SCHEME=${SCHEME:-"http"}
URLS=${URLS:-"${SCHEME}://0.0.0.0:${SERVICE_PORT}"}
PATH_TO_CONF=${PATH_TO_CONF:-"/var/www/services/ASC.Web.HealthChecks.UI/service"}

API_SYSTEM_HOST=${API_SYSTEM_HOST:-"${CONTAINER_PREFIX}api-system:${SERVICE_PORT}"}
BACKUP_HOST=${BACKUP_HOST:-"${CONTAINER_PREFIX}backup:${SERVICE_PORT}"}
BACKUP_BACKGRUOND_TASKS_HOST=${BACKUP_BACKGRUOND_TASKS_HOST:-"${CONTAINER_PREFIX}backup-background-tasks:${SERVICE_PORT}"}
CLEAR_EVENTS_HOST=${CLEAR_EVENTS_HOST:-"${CONTAINER_PREFIX}clear-events:${SERVICE_PORT}"}
FILES_HOST=${FILES_HOST:-"${CONTAINER_PREFIX}files:${SERVICE_PORT}"}
FILES_SERVICES_HOST=${FILES_SERVICES_HOST:-"${CONTAINER_PREFIX}files-services:${SERVICE_PORT}"}
NOTIFY_HOST=${NOTIFY_HOST:-"${CONTAINER_PREFIX}notify:${SERVICE_PORT}"}
PEOPLE_SERVER_HOST=${PEOPLE_SERVER_HOST:-"${CONTAINER_PREFIX}people-server:${SERVICE_PORT}"}
STUDIO_NOTIFY_HOST=${STUDIO_NOTIFY_HOST:-"${CONTAINER_PREFIX}studio-notify:${SERVICE_PORT}"}
API_HOST=${API_HOST:-"${CONTAINER_PREFIX}api:${SERVICE_PORT}"}
STUDIO_HOST=${STUDIO_HOST:-"${CONTAINER_PREFIX}studio:${SERVICE_PORT}"}
SOCKET_HOST=${SOCKET_HOST:-"${CONTAINER_PREFIX}socket:${SERVICE_PORT}"}
SSOAUTH_HOST=${SSOAUTH_HOST:-"${CONTAINER_PREFIX}ssoauth:${SERVICE_PORT}"}
TELEGRAM_HOST=${TELEGRAM_HOST:-"${CONTAINER_PREFIX}telegram:${SERVICE_PORT}"}
AI_HOST=${AI_HOST:-"${CONTAINER_PREFIX}ai:${SERVICE_PORT}"}
AI_SERVICE_HOST=${AI_SERVICE_HOST:-"${CONTAINER_PREFIX}ai-service:${SERVICE_PORT}"}

sed -i "s/\(\"Default\": \).*/\1\"${LOG_LEVEL:-"warning"}\"/" "${PATH_TO_CONF}/appsettings.json"
sed -i "/\"Name\": \"ASC.ApiCache\"/,/{/d" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5010!${API_SYSTEM_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5012!${BACKUP_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5032!${BACKUP_BACKGRUOND_TASKS_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5027!${CLEAR_EVENTS_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5007!${FILES_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5009!${FILES_SERVICES_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5005!${NOTIFY_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5004!${PEOPLE_SERVER_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5000!${API_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5006!${STUDIO_NOTIFY_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5003!${STUDIO_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:9899!${SOCKET_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:9834!${SSOAUTH_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5075!${TELEGRAM_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5157!${AI_HOST}!g" ${PATH_TO_CONF}/appsettings.json
sed -i "s!localhost:5124!${AI_SERVICE_HOST}!g" ${PATH_TO_CONF}/appsettings.json
     
dotnet ${RUN_DLL} --urls=${URLS} 
