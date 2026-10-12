#!/bin/bash
set -xe

SRC_PATH=${1:-"/plugins"}
PLUGIN_NODE_TYPES_VERSION=${PLUGIN_NODE_TYPES_VERSION:-"18.19.0"}

find "$SRC_PATH" -mindepth 2 -maxdepth 2 -type f -name "package.json" -exec dirname {} \; | while read -r PLUGIN_DIR; do
  PLUGIN_NAME=$(jq -r '.name' "$PLUGIN_DIR/package.json")
  echo "=== Building plugin: $PLUGIN_NAME ==="

  cd "$PLUGIN_DIR" || {
    echo "::error:: Cannot cd to $PLUGIN_DIR"
    exit 1
  }

  tmp=$(mktemp)

  jq --arg node_types_version "$PLUGIN_NODE_TYPES_VERSION" '
    . + {
      resolutions: (
        (.resolutions // {}) + {
          "@types/node": $node_types_version
        }
      )
    }
  ' package.json > "$tmp"

  mv "$tmp" package.json

  yarn install --no-cache --ignore-engines || {
    echo "::error:: Yarn install failed for $PLUGIN_NAME"
    exit 1
  }

  yarn run build || {
    echo "::error:: Build failed for $PLUGIN_NAME"
    exit 1
  }

  mkdir -p "$SRC_PATH/publish/$PLUGIN_NAME"

  if [ -f "$PLUGIN_DIR/dist/plugin.zip" ]; then
    unzip -qo "$PLUGIN_DIR/dist/plugin.zip" -d "$SRC_PATH/publish/$PLUGIN_NAME"
  else
    echo "::error:: No plugin.zip found for $PLUGIN_NAME"
    exit 1
  fi
done
