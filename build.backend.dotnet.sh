#!/bin/bash

echo "Start build backend..."
echo

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

if [ $? -eq 0 ]; then
    bash start/stop.sh nopause
    dotnet build ../server/asc.web.slnf /fl1 "/flp1:logfile=asc.web.log;verbosity=normal"
fi

echo

bash start/stop.sh nopause

echo

if [ "$1" != "nopause" ]; then
    read -p "Press Enter to continue..."
fi
