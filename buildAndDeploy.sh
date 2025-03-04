#!/bin/bash

echo "##########################################################"
echo "#########  Start build and deploy  #######################"
echo "##########################################################"
echo

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

if [ $? -eq 0 ]; then
    echo "FRONT-END static"
    bash build.static.sh

    echo "BACK-END"
    bash build.backend.sh

    echo
fi