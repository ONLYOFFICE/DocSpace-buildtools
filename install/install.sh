#!/bin/bash

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "This script is only for macOS"
    exit 1
fi

# Get the current directory path
CURRENT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_ROOT=$(dirname "$CURRENT_PATH")

# Create a temporary directory for modified plist files
TEMP_DIR=$(mktemp -d)

echo "Current project path: $PROJECT_ROOT"
echo "Temporary directory for modified plists: $TEMP_DIR"

# Copy and modify all plist files
for plist in "$CURRENT_PATH/run/macos/"*.plist; do
    filename=$(basename "$plist")
    echo "Processing $filename..."
    
    # Copy to temp directory and replace the variable
    sed "s|\${DOCSPACE_ROOT}|$PROJECT_ROOT|g" "$plist" > "$TEMP_DIR/$filename"
    
    # Copy modified file to ~/Library/LaunchAgents/
    cp "$TEMP_DIR/$filename" ~/Library/LaunchAgents/
    
    # Load the service
    echo "Loading $filename..."
    launchctl unload ~/Library/LaunchAgents/$filename 2>/dev/null || true
    launchctl load ~/Library/LaunchAgents/$filename
done

# Cleanup
rm -rf "$TEMP_DIR"
echo "All services have been installed and loaded."

# Function to check service status
check_service_status() {
    local service_name=$1
    local service_info=$(launchctl list | grep "$service_name$")    
    
    if [ -z "$service_info" ]; then
        return 1
    fi
    
    local pid=$(echo "$service_info" | awk '{print $1}')
    if [ "$pid" -gt 0 ] 2>/dev/null; then
        return 0
    else
        return 2
    fi

}

echo

echo "Waiting 3 seconds for services to start"
sleep 3s

echo

# Check status of loaded services
for service in ~/Library/LaunchAgents/com.onlyoffice.*; do
    service_name=$(basename "$service" .plist)

    if check_service_status "$service_name"; then
        echo "Service $service_name is running"
    elif [ $? -eq 1 ]; then
        echo "Service  $service_name is not loaded"
    else
        echo "Service  $service_name is loaded but not running"
    fi
done