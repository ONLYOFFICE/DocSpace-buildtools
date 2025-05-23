#!/bin/bash
set -Eeuo pipefail

echo "Start build backend..."
echo

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

if [ $? -eq 0 ]; then
    bash start/stop.sh
    dotnet build ../server/asc.web.slnf /fl1 "/flp1:logfile=asc.web.log;verbosity=normal"
fi

echo

bash start/start.sh