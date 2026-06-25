#!/bin/bash
# Usage:
#   offline-archive.sh prepare        — stop containers, free space, pull and retag DocumentServer images
#   offline-archive.sh create ARCH    — patch install scripts, download Docker static binaries, create archives
#   offline-archive.sh build ARCH     — assemble final self-extracting .sh and report size
#   offline-archive.sh upload         — upload artifact to S3 and invalidate CDN cache

set -e

COMMAND="$1"; shift
INSTALL_PATH="${GITHUB_WORKSPACE}/install"

prepare() {
  docker ps -a -q | xargs -r docker stop
  docker ps -a -q | xargs -r docker rm
  docker volume ls -q | xargs -r docker volume rm 2>/dev/null || true
  sudo CLEAN_DOCKER=0 bash "${GITHUB_WORKSPACE}/.github/scripts/free-disk-space-linux.sh"

  for repo in onlyoffice/$( [ "${IS_4TESTING:-true}" != "false" ] && echo 4testing- )documentserver{,-de}; do
    tag=$(curl -s "https://registry.hub.docker.com/v2/repositories/${repo}/tags?page_size=100" \
          | jq -r '.results[].name' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$' | sort -Vr | head -n1)
    [ -z "$tag" ] && { echo "Failed to get tag for $repo"; exit 1; }
    docker pull "${repo}:${tag}"
  done

  while IFS= read -r IMAGE; do
    CLEAN=$(echo "$IMAGE" | sed -E 's/4testing-//; s/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1/')
    docker tag "$IMAGE" "$CLEAN"
    docker rmi "$IMAGE"
  done < <(docker images --format "{{.Repository}}:{{.Tag}}" | grep "4testing-")
}

download_verify() {
  curl -fsSL "$1" -o "$2"
  [ -z "${3:-}" ] && return 0
  CHECKSUM=$(curl -fsSL "$3" | awk '{print $1}')
  [ -n "$CHECKSUM" ] || { echo "::error::Failed to get checksum for $1"; return 1; }
  echo "${CHECKSUM}  $2" | sha256sum -c
}

create() {
  local ARCH="$1"
  local DOCKER_ARCH CNI_ARCH
  if [ "$ARCH" = "arm" ]; then DOCKER_ARCH="aarch64"; CNI_ARCH="arm64";
  else                          DOCKER_ARCH="x86_64";  CNI_ARCH="amd64"; fi

  sed -i 's~\(OFFLINE_INSTALLATION="\|SKIP_HARDWARE_CHECK="\|STACK_MODE="\|NON_INTERACTIVE="\).*"$~\1true"~g' \
    "${INSTALL_PATH}/OneClickInstall/install-Docker.sh"
  DOCSPACE_VERSION=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "docspace-" \
    | sed -E "s/.*:([0-9]+\.[0-9]+\.[0-9]+).*/\1/" | head -n1)
  sed -i "s~\(DOCSPACE_VERSION=\)\"[^\"]*\"~\1\"${DOCSPACE_VERSION}\"~g" \
    "${INSTALL_PATH}/common/offline-self-extracting.sh"

  echo "Downloading Docker static binaries..."
  local BASE_URL="https://download.docker.com/linux/static/stable/${DOCKER_ARCH}"
  local DOCKER_VER; DOCKER_VER=$(curl -fsSL "${BASE_URL}/" | grep -oE 'docker-[0-9]+\.[0-9]+\.[0-9]+\.tgz' | sort -V | tail -n1)
  DOCKER_VER="${DOCKER_VER#docker-}"; DOCKER_VER="${DOCKER_VER%.tgz}"
  local COMPOSE_VER; COMPOSE_VER=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
  local CNI_VER;     CNI_VER=$(curl -fsSL https://api.github.com/repos/containernetworking/plugins/releases/latest | jq -r .tag_name)

  local COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-${DOCKER_ARCH}"
  local CNI_URL="https://github.com/containernetworking/plugins/releases/download/${CNI_VER}/cni-plugins-linux-${CNI_ARCH}-${CNI_VER}.tgz"

  mkdir -p "${INSTALL_PATH}/docker-static"
  cp -r "${INSTALL_PATH}/common/systemd/offline" "${INSTALL_PATH}/docker-static/systemd"

  download_verify "${BASE_URL}/docker-${DOCKER_VER}.tgz"  "${INSTALL_PATH}/docker-static/docker.tgz"
  download_verify "$COMPOSE_URL"                           "${INSTALL_PATH}/docker-static/docker-compose" "${COMPOSE_URL}.sha256"
  download_verify "$CNI_URL"                               "${INSTALL_PATH}/docker-static/cni-plugins.tgz" "${CNI_URL}.sha256"

  echo "Creating Docs compressed archives..."
  mapfile -t DOCS_IMAGES < <(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E 'onlyoffice/documentserver')
  docker save "${DOCS_IMAGES[@]}" | xz --verbose -T0 -z -9e > "${INSTALL_PATH}/docs_images.tar.xz"
  docker rmi "${DOCS_IMAGES[@]}"
  mapfile -t ALL_IMAGES < <(docker images --format "{{.Repository}}:{{.Tag}}")
  docker save "${ALL_IMAGES[@]}" | xz --verbose -T0 -z -9e > "${INSTALL_PATH}/docspace_images.tar.xz"

  echo "Creating docker configuration archive..."
  ( cd "${INSTALL_PATH}/docker" && tar -czvf "${INSTALL_PATH}/docker-stack.tar.gz" \
      --exclude='build.yml'            --exclude='db.dev.yml'          --exclude='dnsmasq.yml' \
      --exclude='docspace.overcome.yml' --exclude='docspace.profiles.yml' \
      --exclude='config/supervisor*'   --exclude='config/mysql*'       --exclude='config/nginx/router/' \
      --exclude='config/createdb.sql'  --exclude='build-*' \
      --exclude='docspace.yml'         --exclude='healthchecks.yml'    --exclude='identity.yml' \
      --exclude='migration-runner.yml' --exclude='notify.yml' \
      ./*.yml .env config )
}

build() {
  local ARCH="$1"
  local SUFFIX=""; [ "$ARCH" = "arm" ] && SUFFIX="-arm"
  local ARTIFACT_NAME="4testing-offline-docspace-installation${SUFFIX}.sh"

  tar -cf "${INSTALL_PATH}/offline-docspace.tar" \
    -C "${INSTALL_PATH}/OneClickInstall" install-Docker-args.sh install-Docker.sh \
    -C "${INSTALL_PATH}" docker-static docker-stack.tar.gz docspace_images.tar.xz docs_images.tar.xz

  rm -rf "${INSTALL_PATH}"/{docspace_images.tar.xz,docs_images.tar.xz,docker-stack.tar.gz,docker-static}

  cat "${INSTALL_PATH}/common/offline-self-extracting.sh" "${INSTALL_PATH}/offline-docspace.tar" \
    > "${INSTALL_PATH}/${ARTIFACT_NAME}"
  chmod +x "${INSTALL_PATH}/${ARTIFACT_NAME}"

  echo "ARTIFACT_NAME=${ARTIFACT_NAME}" >> "$GITHUB_ENV"
  echo "::notice::Archive sizes — $(du -sh "${INSTALL_PATH}/${ARTIFACT_NAME}" | awk '{printf "%s: %s", $2, $1}')"
}

upload() {
  aws s3 cp "${INSTALL_PATH}/${ARTIFACT_NAME}" \
    "${AWS_BUCKET_URL_OCI}/${ARTIFACT_NAME}" \
    --acl public-read --content-type application/x-xz --metadata-directive REPLACE

  local API_STATUS
  API_STATUS=$(aws apigateway test-invoke-method \
    --rest-api-id "$AWS_REST_API_ID" --resource-id "$AWS_RESOURCE_ID" \
    --http-method PUT --path-with-query-string "/prod/download-oo-com" \
    --body "$(jq -c -n '.paths = $ARGS.positional' --args "/docspace/${ARTIFACT_NAME}")" \
    --region us-east-1 --query 'status' --output text || :)
  echo "API Gateway test-invoke status: ${API_STATUS:-<failed>}"
}

case "$COMMAND" in
  prepare) prepare ;;
  create)  create "$@" ;;
  build)   build "$@" ;;
  upload)  upload ;;
  *)       echo "Unknown command: $COMMAND"; exit 1 ;;
esac
