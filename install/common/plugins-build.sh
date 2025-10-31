#!/bin/bash
set -xe

SRC_PATH=${1:-"/plugins"}
MAX_JOBS=${MAX_JOBS:-4}

find "$SRC_PATH" -mindepth 1 -maxdepth 1 -type d \( -exec test -f "{}/yarn.lock" \; -o -exec test -f "{}/package.json" \; \) -print | \
xargs -P "$MAX_JOBS" -I{} bash -c '
  PLUGIN_DIR="$1"; SRC_PATH="$2"; PLUGIN_NAME=$(basename "$PLUGIN_DIR")
  echo "=== Building plugin: $PLUGIN_NAME ==="
  cd "$PLUGIN_DIR" || { echo "::error:: Cannot cd to $PLUGIN_DIR"; exit 0; }

  yarn install --no-cache || { echo "::error:: Yarn install failed for $PLUGIN_NAME"; exit 0; }
  yarn run build || { echo "::error:: Build failed for $PLUGIN_NAME"; exit 0; }

  mkdir -p "$SRC_PATH/publish/$PLUGIN_NAME"
  unzip -qo "$PLUGIN_DIR/dist/plugin.zip" -d "$SRC_PATH/publish/$PLUGIN_NAME" || echo "::error:: No plugin.zip found for $PLUGIN_NAME"
' _ {} "$SRC_PATH"
