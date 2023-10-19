#!/usr/bin/python3

import subprocess

# Execute command to find and filter containers
containers = subprocess.check_output(['docker', 'ps', '-a', '-f', 'label=com.docker.compose.project=docker', '--format={{.ID}}'], text=True).rstrip().split('\n')

print(containers)

#containers = [line.split(' ')[0] for line in output.split('\n') if line and not any(keyword in line for keyword in ["mysql", "rabbitmq", "redis", "elasticsearch", "documentserver"])]

if not containers:
    print("No containers to stop")
    exit()

print("Stop all backend services (containers)")
for c in containers:
    if not c:
        continue
    
    subprocess.run(['docker', 'stop', c])

#print("Stop all backend services (containers)")
#subprocess.run(['docker', 'stop', containers])
