#!/bin/bash
set -xe

SRC_PATH=${1:-"langflow"}

export HOST="127.0.0.1"
export FRONTEND_HOST="${HOST}:3000"
export VITE_BASENAME="/onlyflow/"
export VITE_BACKEND_PROXY_URL="http://${HOST}:7860"

curl -LsSf https://astral.sh/uv/install.sh | HOME=${SRC_PATH} sh && UV=${SRC_PATH}/.local/bin/uv
HOME=${SRC_PATH} ${UV} python install 3.12.9 --directory "${SRC_PATH}"

#backend
cd "${SRC_PATH}"
${UV} venv --directory "${SRC_PATH}" && source "${SRC_PATH}/.venv/bin/activate" && ${UV} sync
cd "${SRC_PATH}/src/backend/base" && ${UV} build --no-sources --wheel
cd "${SRC_PATH}" && ${UV} lock --no-upgrade && ${UV} build --no-sources --wheel

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

#qdrant
for ARCH in x86_64 aarch64; do
    mkdir -p "${SRC_PATH}/qdrant/${ARCH}"
    FILE="qdrant-${ARCH}-unknown-linux-musl.tar.gz"
    wget "https://github.com/qdrant/qdrant/releases/latest/download/${FILE}" 
    tar -xzf "${FILE}" -C "${SRC_PATH}/qdrant/${ARCH}" && rm -rf "${FILE}"
    chmod +x "${SRC_PATH}/qdrant/${ARCH}/qdrant"
done
mkdir -p "${SRC_PATH}/qdrant/config"
echo -e "log_level: WARN\nservice:\n  host: 127.0.0.1\n  http_port: 6333\n  grpc_port: 6334" > "${SRC_PATH}/qdrant/config/config.yaml"
