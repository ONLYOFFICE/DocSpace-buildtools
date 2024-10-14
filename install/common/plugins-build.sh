#!/bin/bash
set -xe

SRC_PATH=${1:-"/plugins"}

for PLUGIN_DIR in $(ls -d ${SRC_PATH}/*); do
  [[ -f ${PLUGIN_DIR}/yarn.lock || -f ${PLUGIN_DIR}/package.json ]] || continue
  PLUGIN_NAME=$(basename ${PLUGIN_DIR})
  echo "Building plugin: ${PLUGIN_NAME}"
  cd ${PLUGIN_DIR} && yarn install && yarn run build
  mkdir -p "${SRC_PATH}/publish/${PLUGIN_NAME}"
  unzip "${PLUGIN_DIR}/dist/plugin.zip" -d "${SRC_PATH}/publish/${PLUGIN_NAME}"
done
