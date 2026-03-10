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
function get_hub_jwt() {
  : "${DOCKER_USERNAME:?Should be set}"
  : "${DOCKER_TOKEN:?Should be set}"

  local response
  response=$(curl -sSL \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${DOCKER_USERNAME}\",\"password\":\"${DOCKER_TOKEN}\"}" \
    "https://hub.docker.com/v2/users/login/" 2>/dev/null)

  HUB_JWT=$(echo "${response}" | jq -r '.token // empty' 2>/dev/null) || true

  if [[ -z "${HUB_JWT}" ]]; then
    error_msg=$(echo "${response}" | jq -r '.detail // .message // "unknown error"' 2>/dev/null) || error_msg="unknown error"
    gha_warning "Docker Hub login failed: ${error_msg} — repository visibility will not be changed automatically"
  fi
}

function make_repo_public() {
  local full_repo="${1%:*}"   # strip tag, e.g. onlyoffice/docspace-api
  local namespace="${full_repo%%/*}"
  local repository="${full_repo#*/}"

  local http_status
  http_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: JWT ${HUB_JWT}" \
    -H "Content-Type: application/json" \
    -d '{"is_private": false}' \
    "https://hub.docker.com/v2/repositories/${namespace}/${repository}/privacy")

  if [[ "${http_status}" == "200" ]]; then
    echo "${COLOR_BLUE}Repository ${namespace}/${repository} is now public${COLOR_RESET}"
  else
    echo "${COLOR_YELLOW}Warning: could not set ${namespace}/${repository} to public (HTTP ${http_status})${COLOR_RESET}" >&2
  fi
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
   
   docker buildx imagetools create --tag ${service_release_tag}:${RELEASE_VERSION%.*} \
                                   --tag ${service_release_tag}:${RELEASE_VERSION} \
                                   --tag ${service_release_tag}:latest \
                                   ${service_source_tag} || local STATUS=$?

   # Make alert
   if [[ ! ${STATUS} ]]; then
     RELEASED_SERVICES+=("${service_release_tag}")
     make_repo_public "${service_release_tag}"
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

  # Authenticate with Docker Hub API for repository visibility management
  get_hub_jwt

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
