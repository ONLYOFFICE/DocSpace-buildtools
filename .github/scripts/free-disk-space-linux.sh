#!/usr/bin/env bash
# ================================================================
# Fast Disk Cleanup Script for CI
# ================================================================

set -euo pipefail
shopt -s nullglob
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# ======= Configurable flags =======
: "${VBOX_SAFE:=0}"        # 1 = keep VirtualBox deps
: "${SHOW_TOP_HOGS:=0}"    # 1 = run du to find largest dirs
: "${CLEAN_PACKAGES:=0}"   # remove big preinstalled packages
: "${CLEAN_DOCKER:=1}"     # prune docker/containerd
: "${CLEAN_SWAP:=1}"       # disable and delete swapfile
: "${CLEAN_DIRS:=1}"       # remove large unused dirs/binaries
: "${CLEAN_LOGS:=1}"       # truncate logs, clean /tmp
: "${CLEAN_DEV_CACHES:=1}" # also remove dev caches (~/.cache, npm, pip, cargo, ...)

# ======= Utils =======
rm_rf(){ echo "[DEL] $*"; sudo rm -rf "$@" & }
printLine() { printf '%*s\n' 80 | tr ' ' "$1"; }
formatByteCount() { numfmt --to=iec-i --suffix=B "$1"; }
getAvailableSpace() { df --output=avail -B1 -l / | awk 'NR==2{print $1}'; }
execAndMeasure(){ local b=$(getAvailableSpace); $1; printSavedSpace $b "$2"; }
topHogs() { du -h --max-depth=1 /usr /opt /var /home 2>/dev/null | sort -rh | head -n 20; }
printSavedSpace(){ local b=${1:-0}; local t=${2:-}; local a=$(getAvailableSpace); local s=$((a-b)); ((s<0))&&s=0; echo "=> $t: Saved $(formatByteCount $s)"; }

# ======= Cleanup functions =======
cleanPackages(){ 
  local patterns='^(temurin-|llvm-|libllvm|libclang-cpp|gcc-|postgresql-|mysql-|kubectl|python3-botocore|linux-azure-.*-headers).*|(google-chrome-stable|microsoft-edge-stable|firefox|azure-cli|google-cloud-cli|google-cloud-cli-anthoscli|powershell|snapd)$'
  local pkgs=$(dpkg-query -W -f='${Package}\n' | grep -E "$patterns" || true)
  [[ -n "$pkgs" ]] && sudo dpkg --purge --force-all $pkgs || true
  sudo rm -rf /var/lib/apt/lists/* /var/cache/apt/* || true
  printLine "="; echo "Top-20 packages by size after cleanup:"
  dpkg-query -Wf='${Installed-Size}\t${Package}\n' | sort -n | tail -n 20
}

cleanDocker() {
  if command -v docker >/dev/null 2>&1; then
    echo "[INFO] Cleaning docker..."
    docker system prune -af --volumes || true
  fi
  if command -v ctr >/dev/null 2>&1; then
    sudo ctr -n moby images prune || true
    sudo ctr -n k8s.io images prune || true
  fi
}

cleanSwap() {
  sudo swapoff -a || true
  rm_rf /mnt/swapfile
}

removeDirs() {
  if [[ "${VBOX_SAFE}" == "1" ]]; then
    rm_rf \
      /opt/google/chrome /opt/microsoft/msedge /usr/lib/firefox* \
      /usr/lib/google-cloud-sdk /opt/az /opt/microsoft/powershell \
      /var/lib/snapd /snap /usr/lib/{postgresql,mysql} /var/lib/{postgresql,mysql} \
      /usr/local/{aws-sam-cli,julia*,lib/android,.ghcup} \
      /usr/local/share/{chromedriver-*,chromium,edge_driver,emacs,gecko_driver,icons,vcpkg,vim} \
      /usr/share/{apache-maven-*,gradle-*,kotlinc,miniconda,php,ri,swift,az_*} \
      /usr/local/bin/{azcopy,bicep,helm,kind,kustomize,minikube,packer,phpunit,pulumi*,stack} \
      /usr/local/lib/node_modules
  else
    rm_rf \
      /usr/lib/jvm/temurin-* /usr/lib/llvm-* /usr/lib/clang /usr/include/clang \
      /usr/lib/gcc /usr/include/c++ \
      /opt/google/chrome /opt/microsoft/msedge /usr/lib/firefox* \
      /usr/lib/google-cloud-sdk /opt/az /opt/microsoft/powershell \
      /var/lib/snapd /snap /usr/lib/{postgresql,mysql} /var/lib/{postgresql,mysql} \
      /usr/local/{aws-sam-cli,julia*,lib/android,.ghcup} \
      /usr/local/share/{chromedriver-*,chromium,cmake-*,edge_driver,emacs,gecko_driver,icons,vcpkg,vim} \
      /usr/share/{apache-maven-*,gradle-*,kotlinc,miniconda,php,ri,swift,az_*} \
      /usr/local/bin/{azcopy,bicep,cmake*,cpack,ctest,helm,kind,kustomize,minikube,packer,phpunit,pulumi*,stack} \
      /usr/local/lib/node_modules /opt/hostedtoolcache/*
  fi
  wait
}

cleanLogsTmp() {
  sudo bash -c '
    rm -rf /var/log/journal/* /var/log/*.log /tmp/* /var/tmp/*;
    find /var/log -type f -exec truncate -s 0 {} +
  '
}

cleanDevCaches() {
  rm_rf "$HOME/.cache" "$HOME/.npm" "$HOME/.yarn" \
        "$HOME/.cargo/registry" "$HOME/.cargo/git" \
        "$HOME/.gradle" "$HOME/.m2/repository" "$HOME/.pip/cache"
  wait
}

# ======= Run =======
AVAILABLE_INITIAL=$(getAvailableSpace)
printLine "="; echo "BEFORE CLEAN-UP"; df -h; printLine "="
[[ "$SHOW_TOP_HOGS" == "1" ]] && topHogs
pids=()
[[ "$CLEAN_PACKAGES" == "1" ]] && execAndMeasure cleanPackages "Packages"
[[ "$CLEAN_DOCKER"     == "1" ]] && { ( execAndMeasure cleanDocker    "Docker"     ) & pids+=($!); }
[[ "$CLEAN_SWAP"       == "1" ]] && { ( execAndMeasure cleanSwap      "Swap"       ) & pids+=($!); }
[[ "$CLEAN_DIRS"       == "1" ]] && { ( execAndMeasure removeDirs     "Dirs"       ) & pids+=($!); }
[[ "$CLEAN_LOGS"       == "1" ]] && { ( execAndMeasure cleanLogsTmp   "Logs/tmp"   ) & pids+=($!); }
[[ "$CLEAN_DEV_CACHES" == "1" ]] && { ( execAndMeasure cleanDevCaches "Dev caches" ) & pids+=($!); }
wait "${pids[@]}"

printLine "="; echo "AFTER CLEAN-UP"; df -h; printLine "="
[[ "$SHOW_TOP_HOGS" == "1" ]] && topHogs

printSavedSpace "$AVAILABLE_INITIAL" "TOTAL"
