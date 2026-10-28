#!/usr/bin/env bash

: "${GITHUB_REPOSITORY:?::error::[FAIL] GITHUB_REPOSITORY not set}"
: "${BRANCH:?::error::[FAIL] BRANCH not set}"
: "${DOCKER_REPOSITORY:?::error::[FAIL] DOCKER_REPOSITORY not set}"
: "${DOCKER_PREFIX:?::error::[FAIL] DOCKER_PREFIX not set}"
: "${DOCKER_TAG:?::error::[FAIL] DOCKER_TAG not set}"
: "${DOCKERHUB_USERNAME:?::error::[FAIL] DOCKERHUB_USERNAME not set}"
: "${DOCKERHUB_TOKEN:?::error::[FAIL] DOCKERHUB_TOKEN not set}"

DOCKERHUB_JWT=$(curl -fsSL -X POST "https://hub.docker.com/v2/users/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${DOCKERHUB_USERNAME}\",\"password\":\"${DOCKERHUB_TOKEN}\"}" \
  | jq -r '.token // empty') || { echo "::error::[FAIL] Docker Hub login failed"; exit 1; }
[ -n "$DOCKERHUB_JWT" ] || { echo "::error::[FAIL] Docker Hub login failed"; exit 1; }

check_image() {
  local REPO="$1" PREFIX="$2" SVC="$3" TAG="$4"
  local IMAGE="${REPO}/${PREFIX}-${SVC}"
  local ACCEPT="application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json"

  if ! curl -sf -o /dev/null -H "Authorization: JWT ${DOCKERHUB_JWT}" \
      "https://hub.docker.com/v2/repositories/${IMAGE}/"; then
    printf "::error::[FAIL]    %-22s (tag %s) repo not found\n" "$SVC" "$TAG"; return 1
  fi

  local TOKEN
  TOKEN=$(curl -fsSL -u "${DOCKERHUB_USERNAME}:${DOCKERHUB_TOKEN}" \
    "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${IMAGE}:pull" \
    | jq -r '.token // empty') || { printf "::error::[FAIL]    %-22s (tag %s) token fetch failed\n" "$SVC" "$TAG"; return 1; }
  [ -n "$TOKEN" ] || { printf "::error::[FAIL]    %-22s (tag %s) empty token\n" "$SVC" "$TAG"; return 1; }

  local DEADLINE=$(( SECONDS + 300 ))
  local RESP
  until RESP=$(curl -fsI \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: ${ACCEPT}" \
      "https://registry-1.docker.io/v2/${IMAGE}/manifests/${TAG}") && echo "$RESP" | grep -q '200'; do
    [ "$SECONDS" -ge "$DEADLINE" ] && { printf "::error::[FAIL]    %-22s (tag %s) manifest not found\n" "$SVC" "$TAG"; return 1; }
    printf '[WAIT]       %-22s (tag %s) manifest not yet available...\n' "$SVC" "$TAG"
    sleep 10
  done

  local CONTENT_TYPE
  CONTENT_TYPE=$(echo "$RESP" | tr -d '\r' | awk -F': *' 'tolower($1) == "content-type" { sub(/;.*/, "", $2); ct = $2 } END { print ct }')
  case "$CONTENT_TYPE" in
    *manifest.list*|*image.index*) printf "[OK]      %-22s tag=%-30s (multi-arch)\n" "$SVC" "$TAG" ;;
    *manifest.v2*|*image.manifest*) printf "[OK]      %-22s tag=%-30s (single-arch: %s)\n" "$SVC" "$TAG" "$CONTENT_TYPE" ;;
    *) printf "::warning::[OK]      %-22s tag=%-30s manifest found, unexpected content type: '%s'\n" "$SVC" "$TAG" "$CONTENT_TYPE" ;;
  esac
}

BUILD_HCL=$(curl -sSL "https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/refs/heads/${BRANCH}/install/docker/build/build.hcl") \
  || { echo "::error::[FAIL] Could not fetch build.hcl"; exit 1; }

mapfile -t SERVICES < <(
  echo "$BUILD_HCL" \
    | REPO=r DOCKER_IMAGE_PREFIX=p DOCKER_TAG=t docker buildx bake -f - default --print 2>/dev/null \
    | jq -r '.target | .[] | .tags[]' \
    | sed -E 's#^r/p-?##; s#:t$##' \
    | grep -vE '^(dotnet|java|node)?$'
)
[ ${#SERVICES[@]} -gt 0 ] || { echo "::error::[FAIL] No images resolved from build.hcl"; exit 1; }

ERROR=0
PIDS=()
trap 'kill 0' SIGINT SIGTERM

for SERVICE in "${SERVICES[@]}"; do
  check_image "${DOCKER_REPOSITORY}" "${DOCKER_PREFIX}" "${SERVICE}" "${DOCKER_TAG}" &
  PIDS+=("$!")
done

for PID in "${PIDS[@]}"; do wait "$PID" || ERROR=1; done
if [ "${ERROR:-0}" -gt 0 ]; then
  echo "::error::[FAIL] Some images failed or repos not found" >&2; exit 1
fi
echo "[OK]      All images are available."
