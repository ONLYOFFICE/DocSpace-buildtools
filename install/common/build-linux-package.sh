#!/bin/bash
set -xeo pipefail

# Usage: build-linux-package.sh deb|rpm
# Downloads sources, applies package branding/versioning, invokes the packaging tool.
#
# Expects in env: BRANCH_BUILDTOOLS, BRANCH_CLIENT, BRANCH_SERVER,
# and either GITHUB_RUN_NUMBER or BUILD_NUMBER.
# PACKAGE_SYSNAME/PRODUCT/LEGACY_PRODUCT/SOURCE_REPO/NODE_VERSION/JAVA_VERSION/
# DOTNET_VERSION/OPENSEARCH_VERSION can be overridden via env; otherwise the defaults below apply.
# Set SKIP_DEB_BUILDDEPS_CHECK=true where nodejs/dotnet/java aren't installed as
# system packages (e.g. nvm-based agents), so dpkg-checkbuilddeps doesn't false-positive.
# Must be run with the working directory at the repository root.

PACKAGE_TYPE=${1:?Usage: $0 deb|rpm}
RUN_NUMBER="${GITHUB_RUN_NUMBER:-${BUILD_NUMBER:?GITHUB_RUN_NUMBER or BUILD_NUMBER must be set}}"
: "${BRANCH_BUILDTOOLS:?BRANCH_BUILDTOOLS must be set}"
: "${BRANCH_CLIENT:?BRANCH_CLIENT must be set}"
: "${BRANCH_SERVER:?BRANCH_SERVER must be set}"

PACKAGE_SYSNAME="${PACKAGE_SYSNAME:-onlyoffice}"
PRODUCT="${PRODUCT:-Apps}"
LEGACY_PRODUCT="${LEGACY_PRODUCT:-docspace}"
SOURCE_REPO="${SOURCE_REPO:-DocSpace}"
NODE_VERSION="${NODE_VERSION:-24}"
JAVA_VERSION="${JAVA_VERSION:-25}"
DOTNET_VERSION="${DOTNET_VERSION:-10.0}"
OPENSEARCH_VERSION="${OPENSEARCH_VERSION:-3.5.0}"

PRODUCT_VERSION=$(grep -oP '\d+\.\d+\.\d+' <<< "${BRANCH_BUILDTOOLS//\//} ${BRANCH_CLIENT//\//} ${BRANCH_SERVER//\//}" | head -n1) || true
PRODUCT_VERSION=${PRODUCT_VERSION:-4.0.0}

case "$PACKAGE_TYPE" in
  deb) SOURCE_DIR="install/deb/debian/source" ;;
  rpm) SOURCE_DIR="install/rpm/SPECS/SOURCES" ;;
  *) echo "Unknown package type: $PACKAGE_TYPE" >&2; exit 1 ;;
esac

[[ "${BRANCH_SERVER}" != "master" ]] && { PLUGINS_BRANCH="develop"; MCP_BRANCH="develop"; } || { PLUGINS_BRANCH="master"; MCP_BRANCH="main"; }
download() { wget -q -O "${SOURCE_DIR}/$3.tar.gz" "https://codeload.github.com/${PACKAGE_SYSNAME}/$1/tar.gz/$2" && echo -e "\e[32m[OK] $3\e[0m" || { echo -e "\e[31m[FAILED] $3\e[0m"; return 1; }; }
PIDS=()
download  "$SOURCE_REPO-buildtools"    "$BRANCH_BUILDTOOLS"        buildtools & PIDS+=($!)
download  "$SOURCE_REPO-client"        "$BRANCH_CLIENT"            client & PIDS+=($!)
download  "$SOURCE_REPO-server"        "$BRANCH_SERVER"            server & PIDS+=($!)
download  "document-templates"         "main/community-server"     DocStore & PIDS+=($!)
download  "$SOURCE_REPO-plugins"       "$PLUGINS_BRANCH"           plugins & PIDS+=($!)
download  "$SOURCE_REPO-mcp"           "$MCP_BRANCH"               mcp & PIDS+=($!)
download  "$SOURCE_REPO-ui-kit-react"  "$BRANCH_CLIENT"            ui-kit & PIDS+=($!)
download  "ASC.Web.Campaigns"          "master"                    campaigns & PIDS+=($!)
download  "document-formats"           "master"                    document-formats & PIDS+=($!)
DOWNLOAD_STATUS=0
for PID in "${PIDS[@]}"; do wait "$PID" || DOWNLOAD_STATUS=1; done
[[ $DOWNLOAD_STATUS -eq 0 ]] || exit $DOWNLOAD_STATUS

if [[ "$PACKAGE_TYPE" == "deb" ]]; then
  cd install/deb/

  if ! grep -qF "${PRODUCT_VERSION}" debian/changelog; then
    TMP=$(mktemp)
    { printf '{{package_name}} ({{package_header_tag_version}}) unstable; urgency=medium\n\n'
      printf '  * Upstream has been updated to version %s.\n\n' "${PRODUCT_VERSION}"
      printf ' -- Ascensio System SIA <support@onlyoffice.com>  %s\n\n' "$(date -R)"
      cat debian/changelog
    } > "${TMP}" && mv "${TMP}" debian/changelog
  fi

  rename -f -v "s/product([^\/]*)$/${PACKAGE_SYSNAME}-${PRODUCT,,}\$1/g" debian/*
  find debian/ -type f -exec sed -i -e "s/{{package_name}}/${PACKAGE_SYSNAME}-${PRODUCT,,}/g" -e "s/{{package_sysname}}/${PACKAGE_SYSNAME}/g" -e "s/{{product}}/${PRODUCT,,}/g" -e "s/{{product_name}}/${PACKAGE_SYSNAME^^} ${PRODUCT}/g" -e "s/{{legacy_product}}/${LEGACY_PRODUCT}/g" -e "s/{{package_header_tag_version}}/${PRODUCT_VERSION}.${RUN_NUMBER}/g" -e "s/{{node_version}}/${NODE_VERSION}/g" -e "s/{{java_version}}/${JAVA_VERSION}/g" -e "s/{{dotnet_version}}/${DOTNET_VERSION}/g" -e "s/{{opensearch_version}}/${OPENSEARCH_VERSION}/g" {} +
  yq -r '.files[] | .name as $n | "cat <<EOF > debian/\($n)\n" + .content + "\nEOF"' debian/files-bundle.yaml | bash

  export DEB_BUILD_OPTIONS="parallel=$(nproc)"
  DPKG_BUILDPACKAGE_ARGS=(-uc -us)
  [[ "${SKIP_DEB_BUILDDEPS_CHECK:-false}" == "true" ]] && DPKG_BUILDPACKAGE_ARGS+=(-d)
  dpkg-buildpackage "${DPKG_BUILDPACKAGE_ARGS[@]}"

elif [[ "$PACKAGE_TYPE" == "rpm" ]]; then
  cd install/rpm/SPECS/

  if ! grep -qF "${PRODUCT_VERSION}" changelog.spec; then
    TMP=$(mktemp)
    awk -v DATE="$(date '+%a %b %d %Y')" -v VERSION="${PRODUCT_VERSION}" ' /^%changelog$/ {
        print
        print "* " DATE " %{packager} - %{version}"
        print "  - Upstream has been updated to version "VERSION".\n"
        next
      } { print } ' changelog.spec > ${TMP} && mv ${TMP} changelog.spec
  fi

  mv ./SOURCES/product.rpmlintrc ./SOURCES/${PRODUCT,,}.rpmlintrc
  sed -i -e '/BuildRequires/d' product.spec
  rpmbuild -D "packager Ascensio System SIA <support@onlyoffice.com>" \
           -D "_topdir $(pwd)" \
           -D "version ${PRODUCT_VERSION}" \
           -D "release ${RUN_NUMBER}" \
           -D "node_version ${NODE_VERSION}" \
           -D "java_version ${JAVA_VERSION}" \
           -D "dotnet_version ${DOTNET_VERSION}" -ba product.spec
fi
