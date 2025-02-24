#!/bin/bash

set -Eeuo pipefail

if [[ "$OSTYPE" == "darwin"* ]]; then
  # Require gnu-sed.
  if ! [ -x "$(command -v gsed)" ]; then
    echo "Error: 'gsed' is not istalled." >&2
    echo "If you are using Homebrew, install with 'brew install gnu-sed'." >&2
    exit 1
  fi
  SED_CMD=gsed
else
  SED_CMD=sed
fi

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_FOLDER="$(dirname "$SCRIPT_DIR")"

# Change to script directory
cd "$SCRIPT_DIR"

pushd "$PARENT_FOLDER" > /dev/null

cd client

# yarn wipe
yarn install

# Build step
yarn build

# Deploy step
yarn deploy

cd ..

# Copy nginx configurations to deploy folder
mkdir -p publish/nginx/sites-enabled
cp -R buildtools/config/nginx/onlyoffice.conf publish/nginx/
${SED_CMD} -i 's/#//g' publish/nginx/onlyoffice.conf

cp -R buildtools/config/nginx/sites-enabled/* publish/nginx/sites-enabled/

# Fix paths in nginx configuration
${SED_CMD} -i "s|ROOTPATH|$PARENT_FOLDER/publish/web/client|g" publish/nginx/sites-enabled/onlyoffice-client.conf
${SED_CMD} -i "s|ROOTPATH|$PARENT_FOLDER/publish/web/management|g" publish/nginx/sites-enabled/onlyoffice-management.conf

if command -v systemctl &> /dev/null; then
    sudo systemctl start nginx
elif command -v brew &> /dev/null; then
    brew services restart openresty
else
    echo "Could not find systemctl or brew command"
    exit 1
fi

popd > /dev/null