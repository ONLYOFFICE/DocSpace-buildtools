#!/bin/bash
# Picks the tested branch and the newest successful appserver.exe Jenkins build of it, then writes step outputs.
# Env: JENKINS_AUTH (login:token, required), BRANCH (override), BUILD (Jenkins build number, overrides BRANCH),
#      STRICT (true: fail when no build is found, otherwise warn and output found=false), JENKINS_HOST (required), REPO_URL.
# The Jenkins host comes from a secret, so the logs mask it; the outputs carry artifact paths relative to the job, never the host.

set -euo pipefail

JENKINS_JOB_URL="https://${JENKINS_HOST:-}/job/appserver.exe"
REPO_URL="${REPO_URL:-https://github.com/${GITHUB_REPOSITORY:-ONLYOFFICE/DocSpace-buildtools}}"
OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/null}"
BRANCH="${BRANCH:-}"
BUILD="${BUILD:-}"
STRICT="${STRICT:-false}"

if [[ -z "${JENKINS_AUTH:-}" ]]; then
  echo "::error::Secret JENKINS_AUTH (login:apitoken of a read-only Jenkins user) is not set"
  exit 1
fi
if [[ -z "${JENKINS_HOST:-}" ]]; then
  echo "::error::Secret JENKINS_HOST (host name of the Jenkins server) is not set"
  exit 1
fi
if [[ -n "$BUILD" && ! "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "::error::jenkins_build must be a build number, got '${BUILD}'"
  exit 1
fi

# The credentials go to curl through stdin, so they never appear in the process list
jenkins_get() {
  printf 'user = "%s"\n' "$JENKINS_AUTH" | curl -fsS -g --max-time 60 --retry 3 --retry-delay 10 -K - "$1"
}

# Branch priority: the newest release/v*, else the newest hotfix/v*, else develop
if [[ -z "$BRANCH" && -z "$BUILD" ]]; then
  heads=$(git ls-remote --heads "$REPO_URL" 'refs/heads/release/v*' 'refs/heads/hotfix/v*' | awk '{sub("refs/heads/", "", $2); print $2}')
  for prefix in release hotfix; do
    BRANCH=$(grep "^${prefix}/v" <<< "$heads" | sort -t/ -k2 -V | tail -n1 || true)
    [[ -n "$BRANCH" ]] && break
  done
  BRANCH="${BRANCH:-develop}"
fi

builds_json=$(jenkins_get "${JENKINS_JOB_URL}/api/json?tree=builds[number,result,building,timestamp,actions[parameters[name,value],remoteUrls,lastBuiltRevision[SHA1]],artifacts[relativePath]]{0,100}")

# One object per build: parameters as a map, the built buildtools commit and the artifact paths
builds=$(jq -c '[.builds[]
  | {number, result, building, timestamp,
     params: ([.actions[]? | (.parameters? // empty)[] | {(.name): .value}] | add // {}),
     sha: ([.actions[]? | select((.remoteUrls? // []) | any(test("/DocSpace-buildtools(\\.git)?$"))) | .lastBuiltRevision.SHA1] | first),
     artifacts: [.artifacts[]?.relativePath]}
  | .branch = ((.params.BUILDTOOLS_GIT_BRANCH // "") | sub("^(origin/|refs/heads/)"; ""))]' <<< "$builds_json")

if [[ -n "$BUILD" ]]; then
  selected=$(jq -c --argjson number "$BUILD" 'map(select(.number == $number)) | first // empty' <<< "$builds")
  description="build #${BUILD}"
else
  selected=$(jq -c --arg branch "$BRANCH" 'map(select(.result == "SUCCESS" and (.building | not) and .branch == $branch
    and (.artifacts | any(test("_Prerequisites_Win-install\\.v[0-9.]+\\.exe$"))))) | max_by(.number) // empty' <<< "$builds")
  description="successful build of ${BRANCH}"
fi

if [[ -z "$selected" ]]; then
  kept=$(jq -r 'map("#\(.number) \(.branch) \(.result // "RUNNING")") | .[:5] | join(", ")' <<< "$builds")
  message="No ${description} among the builds Jenkins keeps for appserver.exe (newest: ${kept})."
  [[ -n "$BUILD" ]] || message+=" Start the Jenkins job appserver.exe with BUILDTOOLS_GIT_BRANCH=${BRANCH}, or run this workflow with the jenkins_build input."
  echo "found=false" >> "$OUTPUT_FILE"
  printf '### Windows installer test skipped\n\n%s\n' "$message" >> "$SUMMARY_FILE"
  if [[ "$STRICT" == "true" ]]; then
    echo "::error::${message}"
    exit 1
  fi
  echo "::warning::${message}"
  exit 0
fi

number=$(jq -r '.number' <<< "$selected")
result=$(jq -r '.result // "RUNNING"' <<< "$selected")
[[ "$result" == "SUCCESS" ]] || echo "::warning::Jenkins build #${number} finished with ${result}; testing its artifacts anyway as requested"

# Artifact path of one installer relative to the job, empty when the build did not produce it
artifact_path() {
  local path
  path=$(jq -r --arg kind "$1" '.artifacts[] | select(test("_\($kind)_Win-install\\.v[0-9.]+\\.exe$"))' <<< "$selected" | head -n1)
  [[ -n "$path" ]] && echo "${number}/artifact/${path}" || true
}
prerequisites_path=$(artifact_path Prerequisites)
if [[ -z "$prerequisites_path" ]]; then
  echo "::error::Jenkins build #${number} has no Prerequisites installer among its artifacts"
  exit 1
fi
version=$(sed -E 's/.*_Win-install\.v([0-9.]+)\.exe$/\1/' <<< "$prerequisites_path")
build_branch=$(jq -r '.branch' <<< "$selected")
sha=$(jq -r '.sha // empty' <<< "$selected")
signed=$(jq -r 'if (.params.SignBuild | tostring) == "true" then "true" else "false" end' <<< "$selected")

{
  echo "found=true"
  echo "build=${number}"
  echo "branch=${build_branch}"
  echo "ref=${sha:-$build_branch}"
  echo "version=${version}"
  echo "signed=${signed}"
  echo "prerequisites_path=${prerequisites_path}"
  echo "community_path=$(artifact_path Community)"
  echo "enterprise_path=$(artifact_path Enterprise)"
  echo "developer_path=$(artifact_path Developer)"
} >> "$OUTPUT_FILE"

echo "Testing Jenkins build #${number}: branch ${build_branch}, commit ${sha:-unknown}, version ${version}, signed ${signed}"
printf '### Windows installer test\n\nJenkins appserver.exe #%s: `%s` at `%s`, version `%s`, SignBuild `%s`\n' \
  "$number" "$build_branch" "${sha:-unknown}" "$version" "$signed" >> "$SUMMARY_FILE"
