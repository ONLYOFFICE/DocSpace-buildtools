#!/usr/bin/python3

import os, sys
import subprocess

rd = os.path.dirname(os.path.abspath(__file__))
root_dir = os.path.abspath(os.path.join(rd, ".."))
docker_dir = os.path.join(root_dir, "buildtools", "install", "docker")

containers = subprocess.check_output(["docker", "ps", "-aq", "-f", "name=^onlyoffice"], encoding='utf-8').strip().split()
images = subprocess.check_output(["docker", "images", "onlyoffice/4testing-docspace*", "-q"], encoding='utf-8').strip().split()

if containers or images:
    print("Clean up containers, volumes or networks")

    print("Remove all backend containers")

    env_vars = {
        "DOCUMENT_SERVER_IMAGE_NAME": "onlyoffice/documentserver-de:latest",
        "Baseimage_Dotnet_Run": "onlyoffice/4testing-docspace-dotnet-runtime:dev",
        "Baseimage_Nodejs_Run": "onlyoffice/4testing-docspace-nodejs-runtime:dev",
        "Baseimage_Proxy_Run": "onlyoffice/4testing-docspace-proxy-runtime:dev",
        "SERVICE_CLIENT": "localhost:5001",
        "BUILD_PATH": "/var/www",
        "SRC_PATH": os.path.join(root_dir, "publish", "services"),
        "ROOT_DIR": root_dir,
        "DATA_DIR": os.path.join(root_dir, "data")
    }

    compose_command = f"docker compose -f {os.path.join(docker_dir, "docspace.profiles.yml")} -f {os.path.join(docker_dir, "docspace.overcome.yml")} --profile \"migration-runner\" --profile \"backend-local\" down --volumes"
    subprocess.run(compose_command, shell=True, env=env_vars)

    print("Remove docker contatiners 'mysql'")
    db_command = f"docker compose -f {os.path.join(docker_dir, 'db.yml')} down --volumes"
    subprocess.run(db_command, shell=True)

    print("Remove docker volumes")
    volumes_command = f"docker volume prune -fa"
    subprocess.run(volumes_command, shell=True)

    print("Remove docker base images (onlyoffice/4testing-docspace)")
    subprocess.run(['docker', 'rmi', '-f'] + images, check=True)

    print("Remove docker networks")
    network_command = f"docker network prune -f"
    subprocess.run(network_command, shell=True)

    print("Remove docker build cache")
    cache_command = f"docker buildx prune -f"
    subprocess.run(cache_command, shell=True)
else:
    print("No containers or images to clean up")
