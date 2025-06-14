# Usage:
#   changelog.sh PACKAGE [REPO] [CHANGELOG_PATH] [MAINTAINER]
#
# PACKAGE: deb | rpm
# REPO: GitHub repository name
# CHANGELOG_PATH:
#   - for deb:   path to debian/changelog (default: ../deb/debian/changelog)
#   - for rpm:   path to SPEC changelog (default: ../rpm/SPECS/changelog.spec)
# MAINTAINER:
#   - for deb:   "Ascensio System SIA <support@onlyoffice.com>"
#   - for rpm:   "%{packager}"

PACKAGE=${1:?Usage: $0 PACKAGE[deb|rpm] [REPO] [PACKAGE_CHANGELOG] [MAINTAINER]}
REPO=${2:-"docspace"}

case "$PACKAGE" in
  deb)
    PACKAGE_CHANGELOG=${3:-"../deb/debian/changelog"}
    MAINTAINER=${4:-"Ascensio System SIA <support@onlyoffice.com>"}
    ;;
  rpm)
    PACKAGE_CHANGELOG=${3:-"../rpm/SPECS/changelog.spec"}
    MAINTAINER=${4:-"%{packager}"}
    ;;
esac

TMP_CHANGELOG=$(mktemp)
trap 'rm -f "$TMP_CHANGELOG" "$TMP_FILE" "$TMP_SPEC_FILE"' EXIT
curl -sL "https://raw.githubusercontent.com/ONLYOFFICE/${REPO}/refs/heads/master/CHANGELOG.md" > "${TMP_CHANGELOG}"

touch "${PACKAGE_CHANGELOG}"
declare -A EXISTING_VERSIONS=()
while IFS= read -r VERSION; do
  EXISTING_VERSIONS["${VERSION}"]=1
done < <(
  if [[ "${PACKAGE}" == "deb" ]]; then
    grep -oP '^{{product}} \(\K[0-9]+\.[0-9]+\.[0-9]+(?=\))' "${PACKAGE_CHANGELOG}"
  elif [[ "${PACKAGE}" == "rpm" ]]; then
    sed -n 's/.*-\s*\([0-9]\+\.[0-9]\+\.[0-9]\+\)$/\1/p' "${PACKAGE_CHANGELOG}"
  fi
)

TMP_FILE=$(mktemp)
for VERSION in $(awk '/^## /{print $2}' "${TMP_CHANGELOG}"); do
  [[ ${EXISTING_VERSIONS[${VERSION}]:-} ]] && continue
  if [[ "${PACKAGE}" == "deb" ]]; then
    printf '%s (%s) unstable; urgency=medium\n\n' "{{product}}" "${VERSION}" >> "${TMP_FILE}"
    awk -v v="$VERSION" 'BEGIN{f=0;it="";subit=0;ml=74}/^## /{if($0=="## "v){f=1;next}else if(f){exit}}f&&/^###/{next}f&&/^\* /&&!/^[[:space:]]+[[:space:]]+\* /{if(it!=""){print_item(it,subit);it="";subit=0}sub(/^\* /,"");it=$0;next}f&&/^[[:space:]]+[[:space:]]+\* /{if(it==""){it="- "$0;sub(/^[[:space:]]+[[:space:]]+\*[[:space:]]*/,"",it);subit=1;next}sub(/^[[:space:]]+[[:space:]]+\*[[:space:]]*/,"- ");it=it"\n"$0;subit=1;next}f&&/^[[:space:]]/&&!/^[[:space:]]*$/&&!/^[[:space:]]+[[:space:]]+\* /{gsub(/^[[:space:]]+/,"");it=it" "$0;next}END{if(it!="")print_item(it,subit)}function print_item(t,s){n=split(t,l,"\n");if(s){wrap_print("  * ",l[1],"  ");for(i=2;i<=n;i++){if(l[i]~/^- /){wrap_print("    - ",substr(l[i],3),"      ")}else{wrap_print("      ",l[i],"      ")}}}else{wrap_print("  * ",t,"    ")}}function wrap_print(p,tx,cp){if(length(p tx)<=ml){print p tx;return}nw=split(tx,w," ");line=p;for(j=1;j<=nw;j++){if(length(line" "w[j])>ml&&line!=p){print line;line=cp}if(line==p||line==cp){line=line w[j]}else{line=line" "w[j]}}if(line!="")print line}' "${TMP_CHANGELOG}" >> "${TMP_FILE}"
    printf '\n -- %s  %s\n\n' "${MAINTAINER}" "$(date -R)" >> "${TMP_FILE}"
  elif [[ "${PACKAGE}" == "rpm" ]]; then
    printf '* %s %s - %s\n' "$(date +"%a %b %d %Y")" "${MAINTAINER}" "${VERSION}" >> "${TMP_FILE}"
    awk -v v="$VERSION" 'BEGIN{f=0;it="";subit=0;ml=67}/^## /{if($0=="## "v){f=1;next}else if(f){exit}}f&&/^###/{next}f&&/^\* /&&!/^[[:space:]]+[[:space:]]+\* /{if(it!=""){print_item(it,subit);it="";subit=0}sub(/^\* /,"");it=$0;next}f&&/^[[:space:]]+[[:space:]]+\* /{if(it==""){it="* "$0;sub(/^[[:space:]]+[[:space:]]+\*[[:space:]]*/,"",it);subit=1;next}sub(/^[[:space:]]+[[:space:]]+\*[[:space:]]*/,"* ");it=it"\n"$0;subit=1;next}f&&/^[[:space:]]/&&!/^[[:space:]]*$/&&!/^[[:space:]]+[[:space:]]+\* /{gsub(/^[[:space:]]+/,"");it=it" "$0;next}END{if(it!="")print_item(it,subit)}function print_item(t,s){n=split(t,l,"\n");if(s){wrap_line("  - ",l[1],ml,0);for(i=2;i<=n;i++){if(l[i]~/^\* /){wrap_line("    * ",substr(l[i],3),ml,4)}else{wrap_line("      ",l[i],ml,6)}}}else{wrap_line("  - ",t,ml,4)}}function wrap_line(p,tx,m,is){line=p;if(length(line tx)<=m){print line tx;return}nw=split(tx,w," ");for(j=1;j<=nw;j++){if(length(line" "w[j])>m&&line!=p){print line;line=sprintf("%"is"s","")}if(line==p||line==sprintf("%"is"s","")){line=line w[j]}else{line=line" "w[j]}}if(line!="")print line}' "${TMP_CHANGELOG}" >> "${TMP_FILE}"
    printf '\n' >> "${TMP_FILE}"
  fi
  echo "Added version ${VERSION} in ${PACKAGE} changelog"
done

if [[ "${PACKAGE}" == "deb" ]]; then
  cat "${TMP_FILE}" "${PACKAGE_CHANGELOG}" > "${PACKAGE_CHANGELOG}.new"
  mv "${PACKAGE_CHANGELOG}.new" "${PACKAGE_CHANGELOG}"
elif [[ "${PACKAGE}" == "rpm" ]]; then
  if [[ -s "${TMP_FILE}" ]]; then
    TMP_SPEC_FILE=$(mktemp)
    { printf '%%changelog\n'
      cat "${TMP_FILE}"
      grep -v '^%changelog$' "${PACKAGE_CHANGELOG}"
    } > "${TMP_SPEC_FILE}"
    mv "${TMP_SPEC_FILE}" "${PACKAGE_CHANGELOG}"
  fi
  rm -f "${TMP_FILE}" "${TMP_SPEC_FILE}"
fi
