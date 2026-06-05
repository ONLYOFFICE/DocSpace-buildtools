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
  | grep -oPm1 '(?<="token":")[^"]+') || { echo "::error::[FAIL] Docker Hub login failed"; exit 1; }

check_image() {
  local REPO="$1"
  local PREFIX="$2"
  local SVC="$3"
  local TAG="$4"
  local IMAGE="${REPO}/${PREFIX}-${SVC}"

  if ! curl -sf -o /dev/null -H "Authorization: JWT ${DOCKERHUB_JWT}" "https://hub.docker.com/v2/repositories/${IMAGE}/"; then
    printf "::error::[FAIL]    %-22s repo not found\n" "${SVC}"; return 1
  fi

  local TOKEN
  TOKEN=$(curl -fsSL -u "${DOCKERHUB_USERNAME}:${DOCKERHUB_TOKEN}" "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${IMAGE}:pull" \
    | grep -oPm1 '(?<="token":")[^"]+') || { printf "::error::[FAIL]    %-22s token fetch failed\n" "${SVC}"; return 1; }
  [[ -z "${TOKEN}" ]] && { printf "::error::[FAIL]    %-22s empty token\n" "${SVC}"; return 1; }

  timeout 300 stdbuf -oL bash -c "
    until curl -fsI -H \"Authorization: Bearer ${TOKEN}\" \
      -H \"Accept: application/vnd.docker.distribution.manifest.v2+json\" \
      https://registry-1.docker.io/v2/${IMAGE}/manifests/${TAG} | grep -q '200'; do
        printf '[WAIT]       %-22s manifest not yet available...\n' '${SVC}'
        sleep 10
      done
  " && printf "[OK]      %-22s\n" "${SVC}" || { printf "::error::[FAIL]    %-22s manifest not found\n" "${SVC}"; return 1; }
}

SERVICES=$(curl -sSL "https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/refs/heads/${BRANCH}/install/docker/build/build.yml" | \
  docker compose -f- config 2>/dev/null | grep -oP 'image: [^/]*/-?\K[^:]+' | grep -vE '^(dotnet|java|node)$')

PIDS=()
trap 'kill 0' SIGINT SIGTERM

for SERVICE in ${SERVICES}; do
  ( check_image "${DOCKER_REPOSITORY}" "${DOCKER_PREFIX}" "${SERVICE}" "${DOCKER_TAG}" ) &
  PIDS+=( "$!" )
done

for PID in "${PIDS[@]}"; do wait "$PID" || ERROR=1; done
[ "${ERROR:-0}" -gt 0 ] && { echo "::error::[FAIL] Some images failed or repos not found" >&2; exit 1; } || echo "[OK]      All images are available."
