#!/bin/bash

############################################################
# Help                                                     #
############################################################
Help()
{
   # Display Help
   echo "Build and run backend and working environment. (Use 'yarn start' to run client -> https://github.com/ONLYOFFICE/DocSpace-client)"
   echo
   echo "Syntax: available params [-h|f|i|c|d|]"
   echo "options:"
   echo "h     Print this Help."
   echo "f     Force rebuild base images."
   echo "s     Run as SAAS otherwise as STANDALONE."
   echo "c     Run as COMMUNITY otherwise ENTERPRISE."
   echo "d     Run dnsmasq."
   echo
}

rd="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
dir=$(builtin cd $rd/../; pwd)
dockerDir="$dir/buildtools/install/docker"
local_ip=$(ipconfig getifaddr en0)

doceditor=${local_ip}:5013
login=${local_ip}:5011
client=${local_ip}:5001
portal_url="http://$local_ip"

force=false
dns=false
standalone=true
community=false

migration_type="STANDALONE" # SAAS
installation_type=ENTERPRISE
document_server_image_name=onlyoffice/documentserver-de:latest

# Get the options
while getopts "h:f:s:c:d:" opt; do
        echo "argument -${opt} called with parameter $OPTARG" >&2
   case $opt in
      h) # Display this Help
         Help
         exit
         ;;
      f) # Force rebuild base images
         force=${OPTARG:-true}
         ;;
      s) # Run as STANDALONE (otherwise SAAS)
         standalone=${OPTARG:-true}
         ;;
      c) # Run as COMMUNITY (otherwise ENTERPRISE)
         community=${OPTARG:-true}
         ;;
      d) # Run dnsmasq
         dns=${OPTARG:-true}
         ;;
      \?) # Invalid option
         echo "Error: Invalid '-$OPTARG' option"
         exit
         ;;
   esac
done

echo "Run script directory:" $dir
echo "Root directory:" $dir
echo "Docker files root directory:" $dockerDir

echo
echo "SERVICE_DOCEDITOR: $doceditor"
echo "SERVICE_LOGIN: $login"
echo "SERVICE_CLIENT: $client"
echo "DOCSPACE_APP_URL: $portal_url"

echo
echo "FORCE REBUILD BASE IMAGES: $force"
echo "Run dnsmasq: $dns"

if [ "$standalone" = false ]; then
    migration_type="SAAS"
fi

if [ "$community" = true ]; then
    installation_type="COMMUNITY"
    document_server_image_name=onlyoffice/documentserver:latest
fi

echo
echo "MIGRATION TYPE: $migration_type"
echo "INSTALLATION TYPE: $installation_type"
echo "DS image: $document_server_image_name"
echo

# Stop all backend services"
$dir/buildtools/start/stop.backend.docker.sh

echo "Run MySQL"

arch_name="$(uname -m)"

existsnetwork=$(docker network ls | awk '{print $2;}' | { grep -x onlyoffice || true; });

if [[ -z ${existsnetwork} ]]; then
    docker network create --driver bridge onlyoffice
fi

if [ "${arch_name}" = "x86_64" ]; then
    echo "CPU Type: x86_64 -> run db.yml"
    docker compose -f $dockerDir/db.yml up -d
elif [ "${arch_name}" = "arm64" ]; then
    echo "CPU Type: arm64 -> run db.yml with arm64v8 image"
    MYSQL_IMAGE=arm64v8/mysql:8.0.32-oracle \
    docker compose -f $dockerDir/db.yml up -d
else
    echo "Error: Unknown CPU Type: ${arch_name}."
    exit 1
fi

if [ "$dns" = true ]; then
    echo "Run local dns server"
    ROOT_DIR=$dir \
    docker compose -f $dockerDir/dnsmasq.yml up -d
fi

echo "Clear publish folder"
rm -rf $dir/publish/services

echo "Build backend services (to "publish/" folder)"
bash $dir/buildtools/install/common/build-services.sh -pb backend-publish -pc Debug -de "$dockerDir/docker-entrypoint.py"

dotnet_version=dev

exists=$(docker images | egrep "onlyoffice/4testing-docspace-dotnet-runtime" | egrep "$dotnet_version" | awk 'NR>0 {print $1 ":" $2}') 

if [ "${exists}" = "" ] || [ "$force" = true ]; then
    echo "Build dotnet base image from source (apply new dotnet config)"
    docker build -t onlyoffice/4testing-docspace-dotnet-runtime:$dotnet_version  -f $dockerDir/Dockerfile.runtime --target dotnetrun .
else 
    echo "SKIP build dotnet base image (already exists)"
fi

node_version=dev

exists=$(docker images | egrep "onlyoffice/4testing-docspace-nodejs-runtime" | egrep "$node_version" | awk 'NR>0 {print $1 ":" $2}') 

if [ "${exists}" = "" ] || [ "$force" = true ]; then
    echo "Build nodejs base image from source"
    docker build -t onlyoffice/4testing-docspace-nodejs-runtime:$node_version  -f $dockerDir/Dockerfile.runtime --target noderun .
else 
    echo "SKIP build nodejs base image (already exists)"
fi

proxy_version=dev

exists=$(docker images | egrep "onlyoffice/4testing-docspace-proxy-runtime" | egrep "$proxy_version" | awk 'NR>0 {print $1 ":" $2}') 

if [ "${exists}" = "" ] || [ "$force" = true ]; then
    echo "Build proxy base image from source (apply new nginx config)"
    docker build -t onlyoffice/4testing-docspace-proxy-runtime:$proxy_version  -f $dockerDir/Dockerfile.runtime --target router .
else 
    echo "SKIP build proxy base image (already exists)"
fi

echo "Run migration and services"
ENV_EXTENSION="dev" \
INSTALLATION_TYPE=$installation_type \
Baseimage_Dotnet_Run="onlyoffice/4testing-docspace-dotnet-runtime:$dotnet_version" \
Baseimage_Nodejs_Run="onlyoffice/4testing-docspace-nodejs-runtime:$node_version" \
Baseimage_Proxy_Run="onlyoffice/4testing-docspace-proxy-runtime:$proxy_version" \
DOCUMENT_SERVER_IMAGE_NAME=$document_server_image_name \
SERVICE_DOCEDITOR=$doceditor \
SERVICE_LOGIN=$login \
SERVICE_CLIENT=$client \
ROOT_DIR=$dir \
BUILD_PATH="/var/www" \
SRC_PATH="$dir/publish/services" \
DATA_DIR="$dir/data" \
APP_URL_PORTAL=$portal_url \
MIGRATION_TYPE=$migration_type \
docker-compose -f $dockerDir/docspace.profiles.yml -f $dockerDir/docspace.overcome.yml --profile migration-runner --profile backend-local up -d

echo
echo "Run script directory:" $dir
echo "Root directory:" $dir
echo "Docker files root directory:" $dockerDir

echo
echo "SERVICE_DOCEDITOR: $doceditor"
echo "SERVICE_LOGIN: $login"
echo "SERVICE_CLIENT: $client"
echo "DOCSPACE_APP_URL: $portal_url"

echo
echo "FORCE REBUILD BASE IMAGES: $force"
echo "Run dnsmasq: $dns"

echo
echo "MIGRATION TYPE: $migration_type"
echo "INSTALLATION TYPE: $installation_type"
echo "DS image: $document_server_image_name"
echo
