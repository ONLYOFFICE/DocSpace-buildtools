#!/bin/bash

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "This script is only for macOS"
    exit 1
fi

# Get the current directory path
CURRENT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_ROOT=$(dirname "$CURRENT_PATH")

#echo "Current project path: $PROJECT_ROOT"

for plist in "$CURRENT_PATH/run/macos/"*.plist; do
    filename=$(basename "$plist")
    echo "Processing $filename..."
    
    launchctl unload ~/Library/LaunchAgents/$filename 2>/dev/null || true
done

#echo

#echo "Waiting 3 seconds for services to stop"
#sleep 3s

echo

# because dotnet does not support launch.d. removed orphaned dotnet processes
#pkill -9 -f dotnet  

echo "All services have been stopped and unloaded."