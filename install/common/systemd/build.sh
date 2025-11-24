#!/bin/bash
set -e

BASEDIR="$(cd $(dirname $0) && pwd)"
BUILD_PATH="$BASEDIR/modules"

while [ "$1" != "" ]; do
    case $1 in
	    
        -bp | --buildpath )
        	if [ "$2" != "" ]; then
				    BUILD_PATH=$2
				    shift
			    fi
		;;
	    
        -pm | --packagemanager )
        	if [ "$2" != "" ]; then
				    PACKAGE_MANAGER=$2
				    shift
			    fi
		;;

        -? | -h | --help )
            echo " Usage: bash build.sh [PARAMETER] [[PARAMETER], ...]"
            echo "    Parameters:"
            echo "      -pm, --packagemanager      dependencies for package manager"
            echo "      -bp, --buildpath           output path"
            echo "      -?, -h, --help             this help"
            echo "  Examples"
            echo "  bash build.sh -bp /etc/systemd/system/"
            exit 0
    ;;

		* )
			echo "Unknown parameter $1" 1>&2
			exit 1
		;;
    esac
  shift
done

PACKAGE_SYSNAME="onlyoffice"
PRODUCT="docspace"
BASE_DIR="/var/www/${PRODUCT}"
PATH_TO_CONF="/etc/${PACKAGE_SYSNAME}/${PRODUCT}"
STORAGE_ROOT="/var/www/${PACKAGE_SYSNAME}/Data"
LOG_DIR="/var/log/${PACKAGE_SYSNAME}/${PRODUCT}"
DOTNET_RUN="/usr/bin/dotnet"
NODE_RUN="/usr/bin/node"
JAVA_RUN="/usr/bin/java -jar"
APP_URLS="http://127.0.0.1"
SYSTEMD_ENVIRONMENT_FILE="${PATH_TO_CONF}/systemd.env"
CORE=" --core:products:folder=${BASE_DIR}/products --core:products:subfolder=server"

SERVICE_NAME=(
	api
	api-system
	socket
	studio-notify
	notify 
	people-server
	files
	files-services
	studio
	backup
	ssoauth
	identity-authorization
	identity-api
	clear-events
	backup-background
	doceditor
	migration-runner
	login
	healthchecks
	sdk
	management
	telegram
	ai
	ai-service
	mcp
	)

reassign_values (){
  if [[ "${PACKAGE_MANAGER}" = "deb" ]]; then
	DEPENDENCY_LIST="mysql.service redis-server.service rabbitmq-server.service"
  else
	DEPENDENCY_LIST="mysqld.service redis.service rabbitmq-server.service"
  fi
  case $1 in
	api )
		SERVICE_PORT="5000"
		WORK_DIR="${BASE_DIR}/studio/ASC.Web.Api/"
		EXEC_FILE="ASC.Web.Api.dll"
	;;
	api-system )
		SERVICE_PORT="5010"
		WORK_DIR="${BASE_DIR}/services/ASC.ApiSystem/"
		EXEC_FILE="ASC.ApiSystem.dll"
	;;
	socket )
		SERVICE_PORT="9899"
		WORK_DIR="${BASE_DIR}/services/ASC.Socket.IO/"
		EXEC_FILE="server.js"
		DEPENDENCY_LIST=""
	;;
	studio-notify )
		SERVICE_PORT="5006"
		WORK_DIR="${BASE_DIR}/services/ASC.Studio.Notify/"
		EXEC_FILE="ASC.Studio.Notify.dll"
	;;
	notify )
		SERVICE_PORT="5005"
		WORK_DIR="${BASE_DIR}/services/ASC.Notify/"
		EXEC_FILE="ASC.Notify.dll"
		CORE_EVENT_BUS=" --core:eventBus:subscriptionClientName=asc_event_bus_notify_queue"
	;;
	people-server )
		SERVICE_PORT="5004"
		WORK_DIR="${BASE_DIR}/products/ASC.People/server/"
		EXEC_FILE="ASC.People.dll"
	;;
	files )
		SERVICE_PORT="5007"
		WORK_DIR="${BASE_DIR}/products/ASC.Files/server/"
		EXEC_FILE="ASC.Files.dll"
	;;
	files-services )
		SERVICE_PORT="5009"
		WORK_DIR="${BASE_DIR}/products/ASC.Files/service/"
		EXEC_FILE="ASC.Files.Service.dll"
		CORE_EVENT_BUS=" --core:eventBus:subscriptionClientName=asc_event_bus_files_service_queue"
		DEPENDENCY_LIST="${DEPENDENCY_LIST} opensearch.service"
	;;
	studio )
		SERVICE_PORT="5003"
		WORK_DIR="${BASE_DIR}/studio/ASC.Web.Studio/"
		EXEC_FILE="ASC.Web.Studio.dll"
		CORE_EVENT_BUS=" --core:eventBus:subscriptionClientName=asc_event_bus_webstudio_queue"
	;;
	backup )
		SERVICE_PORT="5012"
		WORK_DIR="${BASE_DIR}/services/ASC.Data.Backup/"
		EXEC_FILE="ASC.Data.Backup.dll"
	;;
	ssoauth )
		SERVICE_PORT="9834"
		WORK_DIR="${BASE_DIR}/services/ASC.SsoAuth/"
		EXEC_FILE="app.js"
		DEPENDENCY_LIST=""
	;;
	identity-api )
		SERVICE_PORT="9090"
		SPRING_APPLICATION_NAME="ASC.Identity.Registration"
		WORK_DIR="${BASE_DIR}/services/${SPRING_APPLICATION_NAME}/"
		EXEC_FILE="app.jar"
	;;
	identity-authorization )
		SERVICE_PORT="8080"
		SPRING_APPLICATION_NAME="ASC.Identity.Authorization"
		WORK_DIR="${BASE_DIR}/services/${SPRING_APPLICATION_NAME}/"
		EXEC_FILE="app.jar"
	;;
	clear-events )
		SERVICE_PORT="5027"
		WORK_DIR="${BASE_DIR}/services/ASC.ClearEvents/"
		EXEC_FILE="ASC.ClearEvents.dll"
	;;
	backup-background )
		SERVICE_PORT="5032"
		WORK_DIR="${BASE_DIR}/services/ASC.Data.Backup.BackgroundTasks/"
		EXEC_FILE="ASC.Data.Backup.BackgroundTasks.dll"
		CORE_EVENT_BUS=" --core:eventBus:subscriptionClientName=asc_event_bus_backup_queue"
	;;
	doceditor )
		SERVICE_PORT="5013"
		WORK_DIR="${BASE_DIR}/products/ASC.Files/editor/"
		EXEC_FILE="server.js"
		DEPENDENCY_LIST=""
	;;
	migration-runner )
		WORK_DIR="${BASE_DIR}/services/ASC.Migration.Runner/"
		EXEC_FILE="ASC.Migration.Runner.dll"
	;;
	login )
		SERVICE_PORT="5011"
		WORK_DIR="${BASE_DIR}/products/ASC.Login/login/"
		EXEC_FILE="server.js"
		DEPENDENCY_LIST="openresty.service"
	;;
	healthchecks )
		SERVICE_PORT="5033"
		WORK_DIR="${BASE_DIR}/services/ASC.Web.HealthChecks.UI/"
		EXEC_FILE="ASC.Web.HealthChecks.UI.dll"
		DEPENDENCY_LIST=""
	;;
	sdk )
        SERVICE_PORT="5099"
        WORK_DIR="${BASE_DIR}/products/ASC.Sdk/sdk/"
        EXEC_FILE="server.js"
        DEPENDENCY_LIST=""
    ;;
	management )
		SERVICE_PORT="5015"
		WORK_DIR="${BASE_DIR}/products/ASC.Management/management/"
		EXEC_FILE="server.js"
		DEPENDENCY_LIST=""
	;;
	telegram )
		SERVICE_PORT="5075"
		WORK_DIR="${BASE_DIR}/services/ASC.TelegramService/"
		EXEC_FILE="ASC.TelegramService.dll"
		CORE_EVENT_BUS=" --core:eventBus:subscriptionClientName=asc_event_bus_telegram_queue"
	;;
	ai )
		SERVICE_PORT="5157"
		WORK_DIR="${BASE_DIR}/products/ASC.AI/server/"
		EXEC_FILE="ASC.AI.dll"
	;;
	ai-service )
		SERVICE_PORT="5124"
		WORK_DIR="${BASE_DIR}/products/ASC.AI/service/"
		EXEC_FILE="ASC.AI.Service.dll"
		CORE_EVENT_BUS=" --core:eventBus:subscriptionClientName=asc_event_bus_ai_service_queue"
	;;
	mcp )
		SERVICE_PORT="5158"
		WORK_DIR="${BASE_DIR}/products/ASC.AI/mcp/"
		EXEC_FILE="bin/${PACKAGE_SYSNAME}-${PRODUCT}-mcp"
	;;
  esac
  SERVICE_NAME="$1"
  RESTART="always"
  unset SYSTEMD_ENVIRONMENT
  if [[ "${EXEC_FILE}" == *".js" ]]; then
	SERVICE_TYPE="simple"
	EXEC_START="${NODE_RUN} ${WORK_DIR}${EXEC_FILE} --app.port=${SERVICE_PORT} --app.appsettings=${PATH_TO_CONF} --app.environment=\${ENVIRONMENT}"
  elif [[ "${EXEC_FILE}" == *".jar" ]]; then
	SYSTEMD_ENVIRONMENT="SPRING_APPLICATION_NAME=${SPRING_APPLICATION_NAME} SERVER_PORT=${SERVICE_PORT} LOG_FILE_PATH=${LOG_DIR}/${SERVICE_NAME}.log"
	SERVICE_TYPE="notify"
	EXEC_START="${JAVA_RUN} ${WORK_DIR}${EXEC_FILE}"
  elif [[ "${SERVICE_NAME}" = "migration-runner" ]]; then
	SERVICE_TYPE="simple"
	RESTART="on-failure"
	EXEC_START="${DOTNET_RUN} ${WORK_DIR}${EXEC_FILE} standalone=true"
  elif [[ "${SERVICE_NAME}" = "mcp" ]]; then
	SERVICE_TYPE="simple"
	RESTART="always"
	EXEC_START="${NODE_RUN} ${WORK_DIR}${EXEC_FILE}"
  else
	SERVICE_TYPE="notify"
	EXEC_START="${DOTNET_RUN} ${WORK_DIR}${EXEC_FILE} --urls=${APP_URLS}:${SERVICE_PORT} --pathToConf=${PATH_TO_CONF} \
--\$STORAGE_ROOT=${STORAGE_ROOT} --log:dir=${LOG_DIR} --log:name=${SERVICE_NAME}${CORE}${CORE_EVENT_BUS} --ENVIRONMENT=\${ENVIRONMENT}"
	unset CORE_EVENT_BUS
  fi
}

write_to_file () {
  [[ -n ${SYSTEMD_ENVIRONMENT} ]] && sed "/^ExecStart=/a Environment=${SYSTEMD_ENVIRONMENT}" -i $BUILD_PATH/${PRODUCT}-${SERVICE_NAME[$i]}.service
  [[ -n ${DEPENDENCY_LIST} ]] && sed -e "s_\(After=.*\)_\1 ${DEPENDENCY_LIST}_" -e "/After=/a Wants=${DEPENDENCY_LIST}" -i $BUILD_PATH/${PRODUCT}-${SERVICE_NAME[$i]}.service
  sed -i -e 's#${SERVICE_NAME}#'$SERVICE_NAME'#g' -e 's#${WORK_DIR}#'$WORK_DIR'#g' -e "s#\${RESTART}#$RESTART#g" -e "s#\${SYSTEMD_ENVIRONMENT_FILE}#$SYSTEMD_ENVIRONMENT_FILE#g" \
  -e "s#\${EXEC_START}#$EXEC_START#g" -e "s#\${SERVICE_TYPE}#$SERVICE_TYPE#g"  $BUILD_PATH/${PRODUCT}-${SERVICE_NAME[$i]}.service
}

mkdir -p $BUILD_PATH

for i in ${!SERVICE_NAME[@]}; do
  cp $BASEDIR/service $BUILD_PATH/${PRODUCT}-${SERVICE_NAME[$i]}.service
  reassign_values "${SERVICE_NAME[$i]}"
  write_to_file $i
done
