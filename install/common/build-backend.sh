#!/bin/bash
set -xe

SRC_PATH="/AppServer"
ARGS=""

while [ "$1" != "" ]; do
    case $1 in
	    
        -sp | --srcpath )
        	if [ "$2" != "" ]; then
				    SRC_PATH=$2
				    shift
			    fi
		;;

        -ar | --arguments )
          if [ "$2" != "" ]; then
            ARGS=$2
            shift
          fi
    ;;

        -? | -h | --help )
            echo " Usage: bash build-backend.sh [PARAMETER] [[PARAMETER], ...]"
            echo "    Parameters:"
            echo "      -sp, --srcpath             path to AppServer root directory"
            echo "      -ar, --arguments           additional arguments publish the .NET runtime with your application"
            echo "      -?, -h, --help             this help"
            echo "  Examples"
            echo "  bash build-backend.sh -sp /app/AppServer"
            exit 0
    ;;

		* )
			echo "Unknown parameter $1" 1>&2
			exit 1
		;;
    esac
  shift
done
	
echo "== BACK-END-BUILD =="

cd ${SRC_PATH}/server
dotnet build ASC.Web.slnf ${ARGS}
dotnet build ASC.Migrations.sln -o ${SRC_PATH}/server/ASC.Migration.Runner/service/

cd ${SRC_PATH}/client
# Array of names backend services in directory common (Nodejs)
services_name_backend_nodejs=() 
services_name_backend_nodejs+=(ASC.Socket.IO)
services_name_backend_nodejs+=(ASC.SsoAuth)

# Build backend services (Nodejs) 
for i in ${!services_name_backend_nodejs[@]}; do
  echo "== Build ${services_name_backend_nodejs[$i]} project =="
  cd ${SRC_PATH}/server/common/${services_name_backend_nodejs[$i]}
  yarn install --frozen-lockfile
done

# Array of names identity services
IDENTITY_NAMES+=("ASC.Identity.Authorization")
IDENTITY_NAMES+=("ASC.Identity.Registration")
IDENTITY_NAMES+=("ASC.Identity.Migration")

IDENTITY_MODULES+=("authorization/authorization-container")
IDENTITY_MODULES+=("registration/registration-container")
IDENTITY_MODULES+=("infrastructure/infrastructure-migration-runner")

cd ${SRC_PATH}/server/common/ASC.Identity/

# Build and publish identity services
mvn dependency:go-offline
for i in "${!IDENTITY_NAMES[@]}"; do
  echo "== Build ${IDENTITY_NAMES[$i]} project =="
  mvn clean package -DskipTests -pl "${IDENTITY_MODULES[$i]}" -am
  mkdir -p ${IDENTITY_NAMES[$i]} && cp -rf "${IDENTITY_MODULES[$i]}/target/"*.jar "${IDENTITY_NAMES[$i]}/app.jar"
done
