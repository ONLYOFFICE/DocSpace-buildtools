#!/bin/bash
set -xe

SRC_PATH=${1:-"langflow"}

export UV_COMPILE_BYTECODE="1"
export UV_LINK_MODE="copy"

export HOST="127.0.0.1"
export FRONTEND_HOST="${HOST}:3000"
export VITE_BASENAME="/onlyflow/"
export VITE_BACKEND_PROXY_URL="http://${HOST}:7860"
export HOST_API_SERVICE="http://${HOST}:5000"
export HOST_FILES_SERVICE="http://${HOST}:5007"
export HOST_QDRANT_SERVICE="http://${HOST}"
export HOST_QDRANT_PORT="6333"

#frontend
cd "${SRC_PATH}/src/frontend"
npm ci && npm run build
awk '/server\s*{/{f=1;c=0} f{print;c+=gsub(/{/,"{")-gsub(/}/,"}");!c&&(f=0)}' \
    ${SRC_PATH}/docker/frontend/default.conf.template > ${SRC_PATH}/src/frontend/onlyoffice-langflow.conf
sed -i  -e "s#\${FRONTEND_PORT}#${FRONTEND_HOST}#g" \
        -e "s#\${VITE_BASENAME}#${VITE_BASENAME%/}#g" \
        -e "s#\${BACKEND_URL}#${VITE_BACKEND_PROXY_URL}#g" \
        -e "s#usr/share/nginx/html#etc/openresty/html/langflow#g" \
        "${SRC_PATH}/src/frontend/onlyoffice-langflow.conf"

#backend
cd "${SRC_PATH}"
uv sync --frozen --no-install-project --no-editable
uv sync --frozen --no-editable
grep -rl ${SRC_PATH} ${SRC_PATH}/.venv | xargs sed -i "s_${SRC_PATH}_/var/www/docspace/services/langflow_g"
