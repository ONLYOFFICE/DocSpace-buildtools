#!/usr/bin/env bash
# Usage: $0 [PRODUCT] [DEBIAN_CHANGELOG] [MAINTAINER]
PRODUCT=${1:-"docspace"}
DEBIAN_CHANGELOG=${2:-"../deb/debian/changelog"}
MAINTAINER=${3:-"Ascensio System SIA <support@onlyoffice.com>"}

TMP_CHANGELOG=$(mktemp)
trap 'rm -f "$TMP_CHANGELOG" "$TMP_DEBIAN"' EXIT
curl -sL "https://raw.githubusercontent.com/ONLYOFFICE/${PRODUCT}/refs/heads/master/CHANGELOG.md" > "${TMP_CHANGELOG}"

declare -A EXISTING_VERSIONS=()
while IFS= read -r VERSION; do
  EXISTING_VERSIONS["${VERSION}"]=1
done < <(
  grep -E "^${PRODUCT} \([0-9]+\.[0-9]+\.[0-9]+\)" "${DEBIAN_CHANGELOG}" \
    | sed -E "s/^${PRODUCT} \(([0-9]+\.[0-9]+\.[0-9]+)\).*/\1/"
)

TMP_DEBIAN=$(mktemp)
for VERSION in $(awk '/^## /{print $2}' "${TMP_CHANGELOG}"); do
  [[ -n ${EXISTING_VERSIONS[${VERSION}]:-} ]] && continue
  printf '%s (%s) unstable; urgency=medium\n\n' "${PRODUCT}" "${VERSION}" >> "${TMP_DEBIAN}"
  sed -n "/^## ${VERSION}/,/^## /{/^\* /{s/^\* /  * /;p}}" "${TMP_CHANGELOG}" >> "${TMP_DEBIAN}"
  printf '\n--  %s  %s\n\n' "${MAINTAINER}" "$(date -R)" >> "${TMP_DEBIAN}"
  echo "Added version ${VERSION}"
done

cat "${TMP_DEBIAN}" "${DEBIAN_CHANGELOG}" > "${DEBIAN_CHANGELOG}.new"
mv "${DEBIAN_CHANGELOG}.new" "${DEBIAN_CHANGELOG}"
