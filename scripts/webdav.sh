#!/bin/bash

# Store the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$SCRIPT_DIR/.." > /dev/null

# Change to the WebDav project directory
cd "$SCRIPT_DIR/../../server/common/ASC.WebDav/"

# Install yarn dependencies
yarn install --immutable

popd > /dev/null
