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
            echo "      -ba, --build-args          arguments for yarn building"
            echo "      -da, --deploy-args         arguments for yarn deploying"
			echo "      -di, --depbug-info         arguments for yarn debug info configure"
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

if [ "$DEBUG_INFO" = true ]; then
	pip install -r ${SRC_PATH}/buildtools/requirements.txt --break-system-packages
	python3 ${SRC_PATH}/buildtools/debuginfo.py
fi 

cd ${SRC_PATH}/client

yarn install
node common/scripts/before-build.js

CLIENT_PACKAGES+=("@docspace/client")
CLIENT_PACKAGES+=("@docspace/login")
CLIENT_PACKAGES+=("@docspace/doceditor")
CLIENT_PACKAGES+=("@docspace/management")
CLIENT_PACKAGES+=("@docspace/sdk")

export TS_ERRORS_IGNORE=true
for PKG in ${CLIENT_PACKAGES[@]}; do
  yarn workspace ${PKG} ${BUILD_ARGS} $([[ "${PKG}" =~ (client) ]] && echo "--env lint=false")
  yarn workspace ${PKG} ${DEPLOY_ARGS}
done

cp -rf public "${SRC_PATH}/publish/web/"
node common/scripts/minify-common-locales.js
