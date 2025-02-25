#!/bin/bash

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "This script is only for macOS"
    exit 1
fi

launchctl kickstart -k ~/Library/LaunchAgents/com.onlyoffice.* 2>/dev/null || true

echo "Waiting 3 seconds for services to start"

sleep 3s

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