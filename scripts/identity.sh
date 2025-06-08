#!/bin/bash

# Store the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$SCRIPT_DIR/.." > /dev/null

# Change to the identity project directory
cd "$SCRIPT_DIR/../../server/common/ASC.Identity/"

echo "Start build ASC.Identity project..."
echo

echo "ASC.Identity: resolves all project dependencies..."
echo

# Run maven dependency resolution
#mvn dependency:go-offline 

if [ $? -eq 0 ]; then
    echo "ASC.Identity: take the compiled code and package it in its distributable format, such as a JAR..."
    mvn package -DskipTests -q
fi

if [ $? -eq 0 ]; then
    echo "ASC.Identity: build completed"
    echo
fi

popd > /dev/null
