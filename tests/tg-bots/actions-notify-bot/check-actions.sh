#!/usr/bin/env bash

set -e

: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN must be set}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID must be set}"
: "${REPOSITORIES:?REPOSITORIES must be set (repos list)}"

IFS=',' read -ra REPO_LIST <<< "$REPOSITORIES"

for REPO in "${REPO_LIST[@]}"; do
  FAILS="$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/repos/$REPO/actions/runs?per_page=100" | \
    jq --arg start "$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)" '[.workflow_runs[]
      | select(.created_at >= $start and ((.conclusion? // "failure") | test("failure|failed|error|startup_failure")))
      | select(.head_branch | test("^(master|release/.+|hotfix/.+|develop)$"))]')"

  COUNT="$(jq length <<< "$FAILS")"
  if (( COUNT > 0 )); then
    LINES="$(jq -r '[.[] |
      "\u25FB [\(.name[:29] + (if .name|length>26 then "..." else "" end))](\(.html_url)) (\(.head_branch))"
    ] | join("\n")' <<< "$FAILS")"
    RESULT+="*\u274C $COUNT FAILED | 24h | REPO: $REPO*\n$LINES\n\n"
  fi
done

[ -z "$RESULT" ] && echo "No failures in 24h" && exit 0

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{\"chat_id\":\"${TELEGRAM_CHAT_ID}\",\"text\":\"${RESULT}\",\"parse_mode\":\"Markdown\",\"disable_web_page_preview\":true}"

