#!/bin/bash

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "This script is only for macOS"
    exit 1
fi

# Get the current directory path
CURRENT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

echo "Current project path: $CURRENT_PATH"

# Copy and modify all plist files
for plist in "$CURRENT_PATH/run/macos/"*.plist; do
    filename=$(basename "$plist")
        
    # Load the service
    echo "Unloading $filename..."
    launchctl unload ~/Library/LaunchAgents/$filename 2>/dev/null || true
	rm -fr ~/Library/LaunchAgents/$filename 2>/dev/null || true
done

sleep 3s

# because dotnet does not support launch.d. removed orphaned dotnet processes
pkill -9 -f dotnet  

echo "All services have been removed and unloaded."