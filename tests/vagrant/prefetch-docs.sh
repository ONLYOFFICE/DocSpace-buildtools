#!/bin/bash
# Downloads the newest Docs DEB of the dev repository on the CI runner, where aria2 is fast; install.sh puts it into the apt cache of the VM
# Usage: prefetch-docs.sh <docs repo version, e.g. 10.0.4> <output dir>

set -euo pipefail

VER=$1
OUT_DIR=$2
REPO_URL="https://s3.eu-west-1.amazonaws.com/repo-doc-onlyoffice-com/repo/debian"

INDEX=$(curl -fsSL --retry 3 --max-time 120 "${REPO_URL}/dists/stable/${VER}/binary-amd64/Packages")

# One line per onlyoffice-documentserver entry (version, pool path, SHA256), newest version last; read fails on empty input, the check below reports it
read -r PKG_VERSION PKG_FILE PKG_SHA256 < <(awk -v RS= -F'\n' '{
	name = ""; version = ""; file = ""; sha = ""
	for (i = 1; i <= NF; i++) {
		split($i, field, ": ")
		if (field[1] == "Package") name = field[2]
		else if (field[1] == "Version") version = field[2]
		else if (field[1] == "Filename") file = field[2]
		else if (field[1] == "SHA256") sha = field[2]
	}
	if (name == "onlyoffice-documentserver") print version, file, sha
}' <<< "${INDEX}" | sort -V -k1,1 | tail -n 1) || true

[ -n "${PKG_FILE:-}" ] || { echo "::warning::onlyoffice-documentserver not found in the Docs ${VER} repository, nothing to prefetch"; exit 0; }

mkdir -p "${OUT_DIR}"
PKG_NAME=$(basename "${PKG_FILE}")
aria2c -x16 -s16 -k4M --max-tries=5 --retry-wait=3 --file-allocation=none --console-log-level=warn --summary-interval=60 \
	-d "${OUT_DIR}" -o "${PKG_NAME}" "${REPO_URL}/${PKG_FILE}"

# A wrong file would only cost apt a second download, but a clear error here is easier to read
echo "${PKG_SHA256}  ${OUT_DIR}/${PKG_NAME}" | sha256sum -c -
echo "Prefetched onlyoffice-documentserver ${PKG_VERSION} ($(du -m "${OUT_DIR}/${PKG_NAME}" | cut -f1) MB)"
