#!/bin/bash

set -Eeuo pipefail

echo "Start build backend..."
echo

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

if [ $? -eq 0 ]; then
    bash ../control/stop.sh
    dotnet build ../../../server/ASC.Web.slnx /fl1 "/flp1:logfile=asc.web.log;verbosity=normal"
fi

echo "install nodejs projects dependencies..."
echo

# Run all service-build scripts
for script in service-build/*.sh; do
    if [ -f "$script" ]; then
        echo "Run script $(basename "$script")..."
        echo
        bash "$script"
    fi
done

echo

if [ $? -eq 0 ]; then
    bash ../control/start.sh
fi
