#!/usr/bin/python3

import subprocess
import time

start = time.time()
container_ids = subprocess.check_output("docker ps -q -f label=com.docker.compose.project=docker", encoding='utf-8')
containers = container_ids.strip().split()

if containers:
    print("Stop all backend services (containers)")
    subprocess.run(['docker', 'stop'] + containers, check=True)
else:
    print("No containers to stop")

end = time.time()
print("\nElapsed time", end - start)
