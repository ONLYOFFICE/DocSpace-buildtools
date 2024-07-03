#!/usr/bin/env bash

set -e

function get_colors() {
    COLOR_BLUE=$'\e[34m'
    COLOR_GREEN=$'\e[32m'
    COLOR_RED=$'\e[31m'
    COLOR_RESET=$'\e[0m'
    COLOR_YELLOW=$'\e[33m'
    export COLOR_BLUE
    export COLOR_GREEN
    export COLOR_RED
    export COLOR_RESET
    export COLOR_YELLOW
}

function release_service() {
   
   # ex. service_source_tag=onlyoffice/4testing-docspace-service-name:2.5.1.1473
   local service_source_tag=${1}
   
   echo ${service_source_tag}
   
   # ex. service_release_tag=onlyoffice/docspace-service-name:2.5.1.1
   # NOTE: latest tag also will be updated
   local service_release_tag
   service_release_tag=$(echo ${service_source_tag%:*} | sed 's/4testing-//')

   # If specifyed tag look like 2.5.1.1 it will release like 3 different tags: 2.5.1 2.5.1.1 latest
   # Make new image manigest and push it to stable images repository
   
   docker buildx imagetool create --tag ${service_release_tag}:${RELEASE_VERSION%.*} \
                                  --tag ${service_release_tag}:${RELEASE_VERSION} \
                                  --tag ${service_release_tag}:latest \
                                  ${service_source_tag} || local STATUS=$?

   # Make alert
   if [[ ${STATUS} == 0 ]]; then
     RELEASED_SERVICES+=("${service_release_tag}")
   else
     UNRELEASED_SERVICES+=("${service_release_tag}")
   fi
}

function main() {
  # Import all colors
  get_colors

  # Make released|unreleased array
  RELEASED_SERVICES=()
  UNRELEASED_SERVICES=()
  
  # REPO mean hub.docker repo owner ex. onlyoffice 
  : "${REPO:?Should be set}"
  
  # DOCKER_TAG mean tag from 4testing ex. 2.6.1.3123
  : "${DOCKER_TAG:?Should be set}"

  # RELEASED_VERSION mean tag for stable repo 2.6.1.1
  : "${RELEASE_VERSION:?Should be set}"

  # DOCKER_IMAGE_PREFIX mean tag prefix ex. 4testing-docspace
  : "${DOCKER_IMAGE_PREFIX:?Should be set}"

  cd ${GITHUB_WORKSPACE}/install/docker
  
  SERVICES=($(docker buildx bake -f build.yml --print | jq -r '.target | .[] | .tags[]'))
  echo ${SERVICES[@]}
  for service in ${SERVICES[@]}; do
          release_service ${service}
  done

  # Output Result
  echo "Released services"
  for service in ${RELEASED_SERVICES[@]}; do
         echo "${COLOR_GREEN}${service}${COLOR_RESET}"
  done

  # PANIC IF SOME SERVICE WASNT RELEASE
  if [[ -n ${UNRELEASED_SERVICES} ]]; then
    for service in ${UNRELEASED_SERVICES[@]}; do
         echo "${COLOR_RED}PANIC: Service ${service} wasn't relese!${COLOR_RED}"
    done
    exit 1
  fi
}

main
