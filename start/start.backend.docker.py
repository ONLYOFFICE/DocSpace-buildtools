#!/usr/bin/python3

import subprocess
import time

start = time.time()
container_ids = subprocess.check_output("docker ps -aq -f label=com.docker.compose.project=docker", encoding='utf-8')
containers = container_ids.strip().split()

if containers:
    print("Start all backend services (containers)")
    subprocess.run(['docker', 'start'] + containers, check=True)

end = time.time()
print("\nElapsed time", end - start)