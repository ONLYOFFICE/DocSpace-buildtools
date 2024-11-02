#!/usr/bin/python3

import os
import socket
import subprocess
import sys
import getopt
import shutil
import platform


def help():
    # Display Help
    print("Build and run backend and working environment. (Use 'yarn start' to run client -> https://github.com/ONLYOFFICE/DocSpace-client)")
    print()
    print("Syntax: available params [-h|f|s|e=|d|i")
    print("options:")
    print("h     Print this Help.")
    print("f     Force rebuild base images.")
    print("s     Run as SAAS otherwise as STANDALONE.")
    print("e     Run in mode (COMMUNITY (default), ENTERPRISE, DEVELOPER).")
    print("d     Run dnsmasq.")
    print("i     Run identity (oauth2).")
    print("n     Run without stop and build (re-run in different mode).")
    print()


def check_image(image_name):
    return subprocess.check_output(["docker", "images", "--format", "'{{.Repository}}:{{.Tag}}'"], shell=True, text=True).__contains__(image_name)


rd = os.path.dirname(os.path.abspath(__file__))
dir = os.path.abspath(os.path.join(rd, ".."))
dockerDir = os.path.join(dir, "buildtools", "install", "docker")
devAppSettings = os.path.join(
    dir, "buildtools", "config", "appsettings.dev.json")
dnsmasqConf = os.path.join(dir, "buildtools", "config", "dnsmasq.conf")
# networks = socket.gethostbyname_ex(socket.gethostname())
local_ip = "host.docker.internal"  # networks[-1][-1]

# if local_ip == "127.0.0.1":
#     local_ip = networks[-1][0]

# if local_ip == "127.0.0.1":
#     print("Error: Local IP is 127.0.0.1", networks)
#     sys.exit(1)

doceditor = f"{local_ip}:5013"
login = f"{local_ip}:5011"
client = f"{local_ip}:5001"
identity_auth = f"{local_ip}:8080"
identity_api = f"{local_ip}:9090"
management = f"{local_ip}:5015"
portal_url = f"http://{local_ip}"

force = False
dns = False
standalone = True
identity = False
skip_build = False

migration_type = "STANDALONE"  # SAAS
# installation_type = "ENTERPRISE"
env_extension = ""
document_server_image_name = "onlyoffice/documentserver:latest"
base_domain = "localhost"
mysql_database = "docspace"
node_version = "dev"
node_image_name = "onlyoffice/4testing-docspace-nodejs-runtime"
proxy_version = "dev"
proxy_image_name = "onlyoffice/4testing-docspace-proxy-runtime"
dotnet_version = "dev"
dotnet_image_name = "onlyoffice/4testing-docspace-dotnet-runtime"

# Get the options
argv = sys.argv[1:]

try:
    opts, args = getopt.getopt(argv, "hfse:din",
                               ["help",
                                "force",
                                "standalone",
                                "env=",
                                "dns",
                                "identity",
                                "nobuild"
                                ])
except:
    print("Error of parsing arguments")

for opt, arg in opts:
    if opt == "-h":
        help()
        sys.exit()
    elif opt == "-f":
        force = arg if arg else True
    elif opt == "-s":
        standalone = arg if arg else False
    elif opt == "-e":
        env_extension = arg if arg else ""
    elif opt == "-d":
        dns = arg if arg else True
    elif opt == "-i":
        identity = arg if arg else True
    elif opt == "-n":
        skip_build = arg if arg else True
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
print(f"SERVICE_MANAGEMENT: {management}")

if identity == True:
    print(f"SERVICE_IDENTITY: {identity_auth}")
    print(f"SERVICE_IDENTITY_API: {identity_api}")

# print(f"DOCSPACE_APP_URL: {portal_url}")

print()
print("FORCE REBUILD BASE IMAGES:", force)
print("Run dnsmasq:", dns)
print("Run identity:", identity)
print("Skip stop and build:", skip_build)

if standalone == False:
    migration_type = "SAAS"
    base_domain = "docspace.site"
    mysql_database = "docspace"  # "docspace_saas"

if env_extension == "enterprise":
    # installation_type = "ENTERPRISE"
    document_server_image_name = "onlyoffice/documentserver-ee:latest"
    mysql_database = "docspace"  # "docspace_enterprise"
elif env_extension == "developer":
    # installation_type = "DEVELOPER"
    document_server_image_name = "onlyoffice/documentserver-de:latest"
    mysql_database = "docspace"  # "docspace_developer"
else:
    env_extension = ""
    # installation_type = "COMMUNITY"
    document_server_image_name = "onlyoffice/documentserver:latest"
    mysql_database = "docspace"  # "docspace_community"

print()
print("MIGRATION TYPE:", migration_type)
# print("INSTALLATION TYPE:", installation_type)
print("ENV_EXTENSION:", env_extension)
print("BASE DOMAIN:", base_domain)
print("MYSQL DATABASE:", mysql_database)
print("DS image:", document_server_image_name)

print()

if skip_build == False:
    # Stop all backend services
    print("Stop all backend services (containers)")
    subprocess.run(["python", os.path.join(
        dir, "buildtools", "start", "stop.backend.docker.py")])

print("Run MySQL")

arch_name = platform.uname().machine

print(f"PLATFORM {arch_name}")

existsnetwork = subprocess.check_output(
    ["docker", "network", "ls"]).decode("utf-8").splitlines()
existsnetwork = [line.split()[1] for line in existsnetwork]

if "onlyoffice" not in existsnetwork:
    subprocess.run(["docker", "network", "create",
                   "--driver", "bridge", "onlyoffice"])

if arch_name == "x86_64" or arch_name == "AMD64":
    print("CPU Type: x86_64 -> run db.yml")
    os.environ["MYSQL_DATABASE"] = mysql_database
    subprocess.run(["docker", "compose", "-f",
                   os.path.join(dockerDir, "db.yml"), "up", "-d"])
elif arch_name == "arm64":
    print("CPU Type: arm64 -> run db.yml with arm64v8 image")
    os.environ["MYSQL_IMAGE"] = "arm64v8/mysql:8.3.0-oracle"
    os.environ["MYSQL_DATABASE"] = mysql_database
    subprocess.run(["docker", "compose", "-f",
                   os.path.join(dockerDir, "db.yml"), "up", "-d"])
else:
    print("Error: Unknown CPU Type:", arch_name)
    sys.exit(1)

if dns == True:
    print("Run local dns server")
    os.environ["ROOT_DIR"] = dir
    subprocess.run(["docker", "compose", "-f",
                   os.path.join(dockerDir, "dnsmasq.yml"), "up", "-d"])

if skip_build == False:
    print("Clear publish folder")
    shutil.rmtree(os.path.join(dir, "publish/services"), True)

    print("Build backend services (to 'publish/' folder)")
    subprocess.run(["python", os.path.join(dir, "buildtools",
                                           "install", "common", "build-services.py")])


dotnet_image = f"{dotnet_image_name}:{dotnet_version}"
exists = check_image(dotnet_image)

if not exists or force == True:
    print("Build dotnet base image from source (apply new dotnet config)")
    subprocess.run(["docker", "build", "-t", dotnet_image, "-f",
                   os.path.join(dockerDir, "Dockerfile.runtime"), "--target", "dotnetrun", "."])
else:
    print(f"SKIP build {dotnet_image} (already exists)")


node_image = f"{node_image_name}:{node_version}"
exists = check_image(node_image)

if not exists or force == True:
    print("Build nodejs base image from source")
    subprocess.run(["docker", "build", "-t", node_image, "-f",
                   os.path.join(dockerDir, "Dockerfile.runtime"), "--target", "noderun", "."])
else:
    print(f"SKIP build {node_image} (already exists)")

proxy_image = f"{proxy_image_name}:{proxy_version}"
exists = check_image(proxy_image)

if not exists or force == True:
    print("Build proxy base image from source (apply new nginx config)")
    subprocess.run(["docker", "build", "-t", proxy_image, "-f",
                   os.path.join(dockerDir, "Dockerfile.runtime"), "--target", "router", "."])
else:
    print(f"SKIP build {proxy_image} (already exists)")

print("Run migration and services")

os.environ["ENV_EXTENSION"] = env_extension
os.environ["APP_CORE_BASE_DOMAIN"] = base_domain
# os.environ["INSTALLATION_TYPE"] = installation_type
os.environ["Baseimage_Dotnet_Run"] = "onlyoffice/4testing-docspace-dotnet-runtime:" + dotnet_version
os.environ["Baseimage_Nodejs_Run"] = "onlyoffice/4testing-docspace-nodejs-runtime:" + node_version
os.environ["Baseimage_Proxy_Run"] = "onlyoffice/4testing-docspace-proxy-runtime:" + proxy_version
os.environ["DOCUMENT_SERVER_IMAGE_NAME"] = document_server_image_name
os.environ["SERVICE_DOCEDITOR"] = doceditor
os.environ["SERVICE_LOGIN"] = login
os.environ["SERVICE_MANAGEMENT"] = management
os.environ["SERVICE_CLIENT"] = client
os.environ["SERVICE_IDENTITY"] = identity_auth
os.environ["SERVICE_IDENTITY_API"] = identity_api
os.environ["ROOT_DIR"] = dir
os.environ["BUILD_PATH"] = "/var/www"
os.environ["SRC_PATH"] = os.path.join(dir, "publish/services")
os.environ["DATA_DIR"] = os.path.join(dir, "data")
os.environ["APP_URL_PORTAL"] = portal_url
os.environ["MIGRATION_TYPE"] = migration_type
os.environ["MYSQL_DATABASE"] = mysql_database
subprocess.run(["docker", "compose", "-f", os.path.join(dockerDir, "docspace.profiles.yml"), "-f", os.path.join(
    dockerDir, "docspace.overcome.yml"), "--profile", "migration-runner", "--profile", "backend-local", "up", "-d"])

if identity:
    print("Run identity")
    subprocess.run(["docker-compose", "-f",
                   os.path.join(dockerDir, "build-identity.yml"), "up", "-d"])

print()
print("Run script directory:", dir)
print("Root directory:", dir)
print("Docker files root directory:", dockerDir)

print()
print(f"SERVICE_DOCEDITOR: {doceditor}")
print(f"SERVICE_LOGIN: {login}")
print(f"SERVICE_CLIENT: {client}")
print(f"SERVICE_MANAGEMENT: {management}")

if identity == True:
    print(f"SERVICE_IDENTITY: {identity_auth}")
    print(f"SERVICE_IDENTITY_API: {identity_api}")

print()
print("FORCE REBUILD BASE IMAGES:", force)
print("DNSMASQ ENABLED:", dns)

print()
print("MIGRATION TYPE:", migration_type)
# print("INSTALLATION TYPE:", installation_type)
print("ENV_EXTENSION:", env_extension)
print("BASE DOMAIN:", base_domain)
print("MYSQL DATABASE:", mysql_database)
print("DS image:", document_server_image_name)
print()

if dns == True and standalone == False:
    print(f"DOCSPACE_URL: http://localhost.docspace.site")
    print()
    print("!!!DO NOT FORGET TO CONFIGURE DNSMASQ!!!")
    print()
    print("1. Enable DNSMASQ as a local DNS server")
    print(f"2. Edit configuration: {dnsmasqConf}")
    print("3. Replace: server=/site/[your_local_ipv4]")
    print("4. Replace: address=/docspace.site/[your_local_ipv4]")
    print("5. Restart dnsmasq service")
    print("6. Run in terminal: ping docspace.site")
else:
    hostname = socket.gethostname()
    print(f"DOCSPACE_URL: http://{hostname} or http://[your_local_ipv4]")
