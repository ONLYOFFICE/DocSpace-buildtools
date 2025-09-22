#!/usr/bin/env bash
# ================================================================
# Fast Disk Cleanup Script for CI
# ================================================================

set -euo pipefail
shopt -s nullglob
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# ======= Configurable flags =======
: "${DRY_RUN:=0}"          # 1 = dry run (don't delete anything)
: "${SHOW_TOP_HOGS:=0}"    # 1 = run du to find largest dirs
: "${CLEAN_PACKAGES:=1}"   # remove big preinstalled packages
: "${CLEAN_DOCKER:=1}"     # prune docker/containerd
: "${CLEAN_SWAP:=1}"       # disable and delete swapfile
: "${CLEAN_DIRS:=1}"       # remove large unused dirs/binaries
: "${CLEAN_LOGS:=1}"       # truncate logs, clean /tmp
: "${CLEAN_DEV_CACHES:=0}" # also remove dev caches (~/.cache, npm, pip, cargo, …)

# ======= Utils =======
printLine() { printf '%*s\n' 80 | tr ' ' "$1"; }

getAvailableSpace() {
  df --output=avail -B1 -l / | awk 'NR==2{print $1}'
}
formatByteCount() {
  numfmt --to=iec-i --suffix=B "$1"
}
printSavedSpace() {
  local before=$1 title=$2 after saved
  after=$(getAvailableSpace)
  saved=$((after - before))
  ((saved < 0)) && saved=0
  printLine "*"
  echo "=> ${title}: Saved $(formatByteCount "$saved")"
  printLine "*"
}
execAndMeasure() {
  local fn=$1 title=$2
  local before; before=$(getAvailableSpace)
  $fn
  printSavedSpace "$before" "$title"
}
rm_rf() {
  printf '[DEL] %s\n' "$*"
  if [[ "$DRY_RUN" != "1" ]]; then
    sudo rm -rf "$@" &
  fi
}

# ======= Cleanup functions =======
cleanPackages() {
  local pkgs=(
    '^aspnetcore-.*' '^dotnet-.*' '^llvm-.*' '^mongodb-.*'
    'firefox' 'libgl1-mesa-dri' 'mono-devel' 'php.*'
    google-chrome-stable microsoft-edge-stable
    azure-cli google-cloud-sdk google-cloud-cli powershell
  )
  APT="sudo apt-get -o DPkg::Lock::Timeout=60 -y -qq"
  $APT remove --fix-missing "${pkgs[@]}" || true
  $APT autoremove || true
  $APT clean || true
  sudo rm -rf /var/lib/apt/lists/* /var/cache/apt/* || true
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
  local dirs=(
    /usr/local/aws-sam-cli /usr/local/julia* /usr/local/lib/android
    /usr/local/share/chromedriver-* /usr/local/share/chromium
    /usr/local/share/cmake-* /usr/local/share/edge_driver
    /usr/local/share/emacs /usr/local/share/gecko_driver
    /usr/local/share/icons /usr/local/share/powershell
    /usr/local/share/vcpkg /usr/local/share/vim
    /usr/share/apache-maven-* /usr/share/gradle-*
    /usr/share/kotlinc /usr/share/miniconda /usr/share/php
    /usr/share/ri /usr/share/swift
    /usr/local/bin/azcopy /usr/local/bin/bicep
    /usr/local/bin/cmake* /usr/local/bin/cpack /usr/local/bin/ctest
    /usr/local/bin/helm /usr/local/bin/kind /usr/local/bin/kustomize
    /usr/local/bin/minikube /usr/local/bin/packer /usr/local/bin/phpunit
    /usr/local/bin/pulumi* /usr/local/bin/stack /usr/local/.ghcup
    /opt/az /usr/share/az_* /usr/local/lib/node_modules
    /opt/microsoft/powershell /opt/hostedtoolcache/*
  )
  for d in "${dirs[@]}"; do
    rm_rf "$d"
  done
  wait
}

cleanLogsTmp() {
  sudo rm -rf /var/log/journal/* /var/log/*.log || true
  sudo find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
  rm_rf /tmp/* /var/tmp/*
  wait
}

cleanDevCaches() {
  rm_rf "$HOME/.cache" "$HOME/.npm" "$HOME/.yarn" "$HOME/.cargo/registry" "$HOME/.cargo/git" \
        "$HOME/.gradle" "$HOME/.m2/repository" "$HOME/.pip/cache"
  wait
}

topHogs() {
  du -h --max-depth=1 /usr /opt /var /home 2>/dev/null | sort -rh | head -n 20
}

# ======= Run =======
AVAILABLE_INITIAL=$(getAvailableSpace)

printLine "="
echo "BEFORE CLEAN-UP"
df -h
printLine "="
[[ "$SHOW_TOP_HOGS" == "1" ]] && topHogs

pids=()

[[ "$CLEAN_PACKAGES"   == "1" ]] && { ( execAndMeasure cleanPackages  "Packages"   ) & pids+=($!); }
[[ "$CLEAN_DOCKER"     == "1" ]] && { ( execAndMeasure cleanDocker    "Docker"     ) & pids+=($!); }
[[ "$CLEAN_SWAP"       == "1" ]] && { ( execAndMeasure cleanSwap      "Swap"       ) & pids+=($!); }
[[ "$CLEAN_DIRS"       == "1" ]] && { ( execAndMeasure removeDirs     "Dirs"       ) & pids+=($!); }
[[ "$CLEAN_LOGS"       == "1" ]] && { ( execAndMeasure cleanLogsTmp   "Logs/tmp"   ) & pids+=($!); }
[[ "$CLEAN_DEV_CACHES" == "1" ]] && { ( execAndMeasure cleanDevCaches "Dev caches" ) & pids+=($!); }

for pid in "${pids[@]}"; do
  wait "$pid"
done

printLine "="
echo "AFTER CLEAN-UP"
df -h
printLine "="
[[ "$SHOW_TOP_HOGS" == "1" ]] && topHogs

printSavedSpace "$AVAILABLE_INITIAL" "TOTAL"
