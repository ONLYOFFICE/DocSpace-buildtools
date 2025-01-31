#!/bin/bash
set -xe

SRC_PATH="/AppServer"
BUILD_ARGS="build"
DEPLOY_ARGS="deploy"
DEBUG_INFO="true"

while [ "$1" != "" ]; do
    case $1 in
	    
        -sp | --srcpath )
        	if [ "$2" != "" ]; then
				SRC_PATH=$2
				shift
			fi
		;;
        -ba | --build-args )
        	if [ "$2" != "" ]; then
				BUILD_ARGS=$2
				shift
			fi
		;;
        -da | --deploy-args )
        	if [ "$2" != "" ]; then
				DEPLOY_ARGS=$2
				shift
			fi
		;;
		-di | --depbug-info )
        	if [ "$2" != "" ]; then
				DEBUG_INFO=$2
				shift
			fi
		;;
        -? | -h | --help )
            echo " Usage: bash build-backend.sh [PARAMETER] [[PARAMETER], ...]"
            echo "    Parameters:"
            echo "      -sp, --srcpath             path to AppServer root directory"
            echo "      -ba, --build-args          arguments for pnpm building"
            echo "      -da, --deploy-args         arguments for pnpm deploying"
            echo "      -di, --depbug-info         arguments for pnpm debug info configure"
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

echo "== FRONT-END-BUILD =="

cd ${SRC_PATH}
# debug config
if [ "$DEBUG_INFO" = true ]; then
	pip install -r ${SRC_PATH}/buildtools/requirements.txt --break-system-packages
	python3 ${SRC_PATH}/buildtools/debuginfo.py
fi 

CLIENT_PACKAGES+=("@docspace/client")
CLIENT_PACKAGES+=("@docspace/login")
CLIENT_PACKAGES+=("@docspace/doceditor")
CLIENT_PACKAGES+=("@docspace/management")

cd ${SRC_PATH}/client
pnpm install
pnpm nx run-many -t ${BUILD_ARGS} -p "${CLIENT_PACKAGES[@]}" --parallel=4  
pnpm nx run-many -t ${DEPLOY_ARGS} -p "${CLIENT_PACKAGES[@]}" --parallel=4
