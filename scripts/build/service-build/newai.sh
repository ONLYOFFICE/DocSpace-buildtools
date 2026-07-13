#!/bin/bash

# Store the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$SCRIPT_DIR/.." > /dev/null

# Change to the NewAi project directory
cd "$SCRIPT_DIR/../../../../server/common/ASC.NewAi/"

# Install yarn dependencies
yarn install --immutable

popd > /dev/null
