#!/usr/bin/python3

import os
import socket
import subprocess
import sys, getopt
import shutil
import platform

def help():
    # Display Help
    print("Build and run backend and working environment. (Use 'yarn start' to run client -> https://github.com/ONLYOFFICE/DocSpace-client)")
    print()
    print("Syntax: available params [-h|f|s|c|d|]")
    print("options:")
    print("h     Print this Help.")
    print("f     Force rebuild base images.")
    print("s     Run as SAAS otherwise as STANDALONE.")
    print("c     Run as COMMUNITY otherwise ENTERPRISE.")
    print("d     Run dnsmasq.")
    print()


rd = os.path.dirname(os.path.abspath(__file__))
dir = os.path.abspath(os.path.join(rd, ".."))
dockerDir = os.path.join(dir, "buildtools", "install", "docker")
networks = socket.gethostbyname_ex(socket.gethostname())
local_ip = networks[-1][-1]

if local_ip == "127.0.0.1":
    local_ip = networks[-1][0]

if local_ip == "127.0.0.1":
    print("Error: Local IP is 127.0.0.1", networks)
    sys.exit(1)

doceditor = f"{local_ip}:5013"
login = f"{local_ip}:5011"
client = f"{local_ip}:5001"
management = f"{local_ip}:5015"
portal_url = f"http://{local_ip}"

force = False
dns = False
standalone = True
community = False

migration_type = "STANDALONE" # SAAS
installation_type = "ENTERPRISE"
document_server_image_name = "onlyoffice/documentserver-de:latest"

# Get the options
opts, args = getopt.getopt(sys.argv[1:], "hfscd")
for opt, arg in opts:
    if opt == "-h":
        help()
        sys.exit()
    elif opt == "-f":
        force = arg if arg else True
    elif opt == "-s":
        standalone = arg if arg else False
    elif opt == "-c":
        community = arg if arg else True
    elif opt == "-d":
        dns = arg if arg else True
    else:
        print("Error: Invalid '-" + opt + "' option")
        sys.exit()

print("Run script directory:", dir)
print("Root directory:", dir)
print("Docker files root directory:", dockerDir)

print()
print(f"SERVICE_DOCEDITOR: {doceditor}")
print(f"SERVICE_LOGIN: {login}")
print(f"SERVICE_CLIENT: {client}")
print(f"DOCSPACE_APP_URL: {portal_url}")

print()
print("FORCE REBUILD BASE IMAGES:", force)
print("Run dnsmasq:", dns)

if standalone == False:
    migration_type = "SAAS"

if community == True:
    installation_type = "COMMUNITY"
    document_server_image_name = "onlyoffice/documentserver:latest"

print()
print("MIGRATION TYPE:", migration_type)
print("INSTALLATION TYPE:", installation_type)
print("DS image:", document_server_image_name)
print()

# Stop all backend services
subprocess.run(["python", os.path.join(dir, "buildtools", "start", "stop.backend.docker.py")])

print("Run MySQL")

arch_name = platform.uname().machine

print(f"PLATFORM {arch_name}")

existsnetwork = subprocess.check_output(["docker", "network", "ls"]).decode("utf-8").splitlines()
existsnetwork = [line.split()[1] for line in existsnetwork]

if "onlyoffice" not in existsnetwork:
    subprocess.run(["docker", "network", "create", "--driver", "bridge", "onlyoffice"])

if arch_name == "x86_64" or arch_name == "AMD64":
    print("CPU Type: x86_64 -> run db.yml")
    subprocess.run(["docker", "compose", "-f", os.path.join(dockerDir, "db.yml"), "up", "-d"])
elif arch_name == "arm64":
    print("CPU Type: arm64 -> run db.yml with arm64v8 image")
    os.environ["MYSQL_IMAGE"] = "arm64v8/mysql:8.3.0-oracle"
    subprocess.run(["docker", "compose", "-f", os.path.join(dockerDir, "db.yml"), "up", "-d"])
else:
    print("Error: Unknown CPU Type:", arch_name)
    sys.exit(1)

if dns == True:
    print("Run local dns server")
    os.environ["ROOT_DIR"] = dir
    subprocess.run(["docker", "compose", "-f", os.path.join(dockerDir, "dnsmasq.yml"), "up", "-d"])

print("Clear publish folder")
shutil.rmtree(os.path.join(dir, "publish/services"), True)

print("Build backend services (to 'publish/' folder)")
subprocess.run(["python", os.path.join(dir, "buildtools", "install", "common", "build-services.py")])

def check_image(image_name):
    return subprocess.check_output(["docker", "images", "--format", "'{{.Repository}}:{{.Tag}}'"], shell=True, text=True).__contains__(image_name)

dotnet_image_name = "onlyoffice/4testing-docspace-dotnet-runtime"
dotnet_version = "dev"
dotnet_image = f"{dotnet_image_name}:{dotnet_version}"

exists = check_image(dotnet_image)

if not exists or force == True:
    print("Build dotnet base image from source (apply new dotnet config)")
    subprocess.run(["docker", "build", "-t", dotnet_image, "-f", os.path.join(dockerDir, "Dockerfile.runtime"), "--target", "dotnetrun", "."])
else:
    print(f"SKIP build {dotnet_image} (already exists)")

node_image_name = "onlyoffice/4testing-docspace-nodejs-runtime"
node_version = "dev"
node_image = f"{node_image_name}:{node_version}"

exists = check_image(node_image)

if not exists or force == True:
    print("Build nodejs base image from source")
    subprocess.run(["docker", "build", "-t", node_image, "-f", os.path.join(dockerDir, "Dockerfile.runtime"), "--target", "noderun", "."])
else:
    print(f"SKIP build {node_image} (already exists)")

proxy_image_name = "onlyoffice/4testing-docspace-proxy-runtime"
proxy_version = "dev"
proxy_image = f"{proxy_image_name}:{proxy_version}"

exists = check_image(proxy_image)

if not exists or force == True:
    print("Build proxy base image from source (apply new nginx config)")
    subprocess.run(["docker", "build", "-t", proxy_image, "-f", os.path.join(dockerDir, "Dockerfile.runtime"), "--target", "router", "."])
else:
    print(f"SKIP build {proxy_image} (already exists)")

print("Run migration and services")

os.environ["ENV_EXTENSION"] = "dev"
os.environ["INSTALLATION_TYPE"] = installation_type
os.environ["Baseimage_Dotnet_Run"] = "onlyoffice/4testing-docspace-dotnet-runtime:" + dotnet_version
os.environ["Baseimage_Nodejs_Run"] = "onlyoffice/4testing-docspace-nodejs-runtime:" + node_version
os.environ["Baseimage_Proxy_Run"] = "onlyoffice/4testing-docspace-proxy-runtime:" + proxy_version
os.environ["DOCUMENT_SERVER_IMAGE_NAME"] = document_server_image_name
os.environ["SERVICE_DOCEDITOR"] = doceditor
os.environ["SERVICE_LOGIN"] = login
os.environ["SERVICE_MANAGEMENT"] = management
os.environ["SERVICE_CLIENT"] = client
os.environ["ROOT_DIR"] = dir
os.environ["BUILD_PATH"] = "/var/www"
os.environ["SRC_PATH"] = os.path.join(dir, "publish/services")
os.environ["DATA_DIR"] = os.path.join(dir, "data")
os.environ["APP_URL_PORTAL"] = portal_url
os.environ["MIGRATION_TYPE"] = migration_type
subprocess.run(["docker-compose", "-f", os.path.join(dockerDir, "docspace.profiles.yml"), "-f", os.path.join(dockerDir, "docspace.overcome.yml"), "--profile", "migration-runner", "--profile", "backend-local", "up", "-d"])

print()
print("Run script directory:", dir)
print("Root directory:", dir)
print("Docker files root directory:", dockerDir)

print()
print(f"SERVICE_DOCEDITOR: {doceditor}")
print(f"SERVICE_LOGIN: {login}")
print(f"SERVICE_MANAGEMENT: {management}")
print(f"SERVICE_CLIENT: {client}")
print(f"DOCSPACE_APP_URL: {portal_url}")

print()
print("FORCE REBUILD BASE IMAGES:", force)
print("Run dnsmasq:", dns)

print()
print("MIGRATION TYPE:", migration_type)
print("INSTALLATION TYPE:", installation_type)
print("DS image:", document_server_image_name)
print()
