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

# GitHub Actions workflow command helpers
function gha_error()   { echo "::error::${*}"; }
function gha_warning() { echo "::warning::${*}"; }
function gha_notice()  { echo "::notice::${*}"; }
function gha_group()   { echo "::group::${*}"; }
function gha_endgroup(){ echo "::endgroup::"; }

function validate_version_format() {
  local version="${1}"
  local label="${2}"
  if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    gha_error "${label} '${version}' does not match expected format N.N.N or N.N.N.N"
    exit 1
  fi
}

function check_source_image_exists() {
  local source_tag="${1}"
  local image="${source_tag%:*}"
  local tag="${source_tag##*:}"
  local namespace="${image%%/*}"
  local repository="${image#*/}"

  local http_status
  http_status=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://hub.docker.com/v2/repositories/${namespace}/${repository}/tags/${tag}/")

  if [[ "${http_status}" != "200" ]]; then
    gha_error "Source image not found on Docker Hub: ${source_tag} (HTTP ${http_status})"
    return 1
  fi
}

function get_hub_jwt() {
  if [[ -z "${DOCKER_USERNAME_PAT}" || -z "${DOCKER_TOKEN_PAT}" ]]; then
    gha_warning "DOCKER_USERNAME_PAT / DOCKER_TOKEN_PAT are not set - repository visibility will not be changed automatically"
    return 0
  fi

  local response
  response=$(curl -sSL \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${DOCKER_USERNAME_PAT}\",\"password\":\"${DOCKER_TOKEN_PAT}\"}" \
    "https://hub.docker.com/v2/users/login/" 2>/dev/null)

  HUB_JWT=$(echo "${response}" | jq -r '.token // empty' 2>/dev/null) || true

  if [[ -z "${HUB_JWT}" ]]; then
    error_msg=$(echo "${response}" | jq -r '.detail // .message // "unknown error"' 2>/dev/null) || error_msg="unknown error"
    gha_warning "Docker Hub login failed: ${error_msg}"
  fi
}

function make_repo_public() {
  [[ -z "${HUB_JWT}" ]] && return 0
  local full_repo="${1%:*}"
  local namespace="${full_repo%%/*}"
  local repository="${full_repo#*/}"

  local http_status
  http_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: JWT ${HUB_JWT}" \
    -H "Content-Type: application/json" \
    -d '{"is_private": false}' \
    "https://hub.docker.com/v2/repositories/${namespace}/${repository}/privacy")

  if [[ "${http_status}" != "200" ]]; then
    gha_warning "Cannot set ${namespace}/${repository} to public (HTTP ${http_status})"
  fi
}
function release_service() {
   
   # ex. service_source_tag=onlyoffice/4testing-docspace-service-name:2.5.1.1473
   local service_source_tag="${1}"
   local service_release_tag
   
   echo "${service_source_tag}"
   
   # ex. service_release_tag=onlyoffice/docspace-service-name:2.5.1.1
   # NOTE: latest tag also will be updated
   service_release_tag=$(echo "${service_source_tag%:*}" | sed 's/4testing-//')

   # Verify source image is available before attempting release
   if ! check_source_image_exists "${service_source_tag}"; then
     UNRELEASED_SERVICES+=("${service_release_tag}")
     return
   fi

   # If specifyed tag look like 2.5.1.1 it will release like 3 different tags: 2.5.1 2.5.1.1 latest
   # Make new image manigest and push it to stable images repository
   
   local STATUS=0
   docker buildx imagetools create --tag "${service_release_tag}:${RELEASE_VERSION%.*}" \
                                   --tag "${service_release_tag}:${RELEASE_VERSION}" \
                                   --tag "${service_release_tag}:latest" \
                                   "${service_source_tag}" || STATUS=$?

   # Make alert
   if [[ ${STATUS} -eq 0 ]]; then
     RELEASED_SERVICES+=("${service_release_tag}")
     get_hub_jwt
     make_repo_public "${service_release_tag}"
   else
     gha_error "docker buildx imagetools create failed for ${service_release_tag} (exit code ${STATUS})"
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

  # Validate version formats early to fail fast
  validate_version_format "${DOCKER_TAG}"      "source_version (DOCKER_TAG)"
  validate_version_format "${RELEASE_VERSION}" "release_version (RELEASE_VERSION)"

  cd "${GITHUB_WORKSPACE}/install/docker"
  
  SERVICES=($(docker buildx bake -f build/build.yml --print | jq -r '.target | .[] | .tags[]'))

  if [[ ${#SERVICES[@]} -eq 0 ]]; then
    gha_error "No services found in build.yml — bake returned an empty target list"
    exit 1
  fi

  for service in "${SERVICES[@]}"; do
    release_service "${service}"
  done

  # Output Result
  gha_group "Released services (${#RELEASED_SERVICES[@]})"
  for service in "${RELEASED_SERVICES[@]}"; do
    echo "${COLOR_GREEN}${service}${COLOR_RESET}"
  done
  gha_endgroup

  # PANIC IF SOME SERVICE WASNT RELEASE
  if [[ ${#UNRELEASED_SERVICES[@]} -gt 0 ]]; then
    gha_group "Failed services (${#UNRELEASED_SERVICES[@]})"
    for service in "${UNRELEASED_SERVICES[@]}"; do
      gha_error "Service was not released: ${service}"
    done
    gha_endgroup
    exit 1
  fi
}

main
