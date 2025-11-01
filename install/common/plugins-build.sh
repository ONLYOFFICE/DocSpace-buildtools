#!/bin/bash
set -xe

SRC_PATH=${1:-"/plugins"}

find "$SRC_PATH" -mindepth 2 -maxdepth 2 -type f -name "package.json" -printf '%h\n' | while read -r PLUGIN_DIR; do
  PLUGIN_NAME=$(grep -oP '"name"\s*:\s*"\K([^"\\]|\\.)+(?="\s*[},])' "$PLUGIN_DIR/package.json")
  echo "=== Building plugin: $PLUGIN_NAME ==="
  cd "$PLUGIN_DIR" || { echo "::error:: Cannot cd to $PLUGIN_DIR"; exit 1; }

  yarn install --no-cache || { echo "::error:: Yarn install failed for $PLUGIN_NAME"; exit 1; }
  yarn run build || { echo "::error:: Build failed for $PLUGIN_NAME"; exit 1; }

  mkdir -p "$SRC_PATH/publish/$PLUGIN_NAME"
  unzip -qo "$PLUGIN_DIR/dist/plugin.zip" -d "$SRC_PATH/publish/$PLUGIN_NAME" || echo "::error:: No plugin.zip found for $PLUGIN_NAME"
done
