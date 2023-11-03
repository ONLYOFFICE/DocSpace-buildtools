#!/usr/bin/python3

import os
import stat
import subprocess
import shutil

SRC_PATH = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
BUILD_PATH = os.path.join(SRC_PATH, "publish")

print(f"SRC_PATH = {SRC_PATH}")
print(f"BUILD_PATH = {BUILD_PATH}")

BACKEND_NODEJS_SERVICES = ["ASC.Socket.IO", "ASC.SsoAuth"]
BACKEND_DOTNETCORE_SERVICES = ["ASC.Files", "ASC.People", "ASC.Data.Backup", "ASC.Files.Service", "ASC.Notify", "ASC.Studio.Notify", "ASC.Web.Api", "ASC.Web.Studio", "ASC.Data.Backup.BackgroundTasks", "ASC.ClearEvents", "ASC.ApiSystem", "ASC.Web.HealthChecks.UI"]
SELF_CONTAINED = "false"
PUBLISH_CNF = "Debug"

FRONTEND_BUILD_ARGS = "build"
FRONTEND_DEPLOY_ARGS = "deploy"
DEBUG_INFO_CHECK = ""
MIGRATION_CHECK = "true"
DOCKER_ENTRYPOINT="docker-entrypoint.py"
DOCKER_ENTRYPOINT_PATH = os.path.join(SRC_PATH, "buildtools", "install", "docker", DOCKER_ENTRYPOINT)

if os.path.exists(os.path.join(BUILD_PATH, "services")):
    print("== Clean up services ==")
    shutil.rmtree(os.path.join(BUILD_PATH, "services"))

print("== Build ASC.Web.slnf ==")
subprocess.run(["dotnet", "build", os.path.join(SRC_PATH, "server", "ASC.Web.slnf")])

print("== Build ASC.Migrations.sln ==")
subprocess.run(["dotnet", "build", os.path.join(SRC_PATH, "server", "ASC.Migrations.sln"), "-o", os.path.join(BUILD_PATH, "services", "ASC.Migration.Runner", "service")])

print("== Add docker-migration-entrypoint.sh to ASC.Migration.Runner ==")
file_path = os.path.join(BUILD_PATH, "services", "ASC.Migration.Runner", "service", "docker-migration-entrypoint.sh")

with open(os.path.join(SRC_PATH, "buildtools", "install", "docker", "docker-migration-entrypoint.sh"), "r") as file:
    content = file.read().replace("\r", "")
    with open(file_path, "w") as new_file:
        new_file.write(content)

st = os.stat(file_path)
os.chmod(file_path, st.st_mode | stat.S_IEXEC)

format = "zip"

for service in BACKEND_NODEJS_SERVICES:
    print(f"== Build {service} project ==")
    src =  os.path.join(SRC_PATH, "server", "common", service)
    subprocess.run(["yarn", "install"], cwd=src)

    dst = os.path.join(BUILD_PATH, "services", service, "service")
    if not os.path.exists(dst):
        os.makedirs(dst, exist_ok=True)

    archive = os.path.join(BUILD_PATH, "services", service, f"service.{format}")

    print("Make service archive", archive)

    shutil.make_archive(root_dir=src, format=format, base_name=dst)

    print("Unpack service archive", archive)
    shutil.unpack_archive(archive, dst)

    print("Remove service archive", archive)
    os.remove(archive)

    print(f"== Add docker-entrypoint.py to {service}")
    shutil.copyfile(DOCKER_ENTRYPOINT_PATH, os.path.join(dst, DOCKER_ENTRYPOINT))

print("== Publish ASC.Web.slnf ==")
subprocess.run(["dotnet", "publish", os.path.join(SRC_PATH, "server", "ASC.Web.slnf"), "-p", "PublishProfile=FolderProfile"])

for service in BACKEND_DOTNETCORE_SERVICES:
    print(f"== Add {DOCKER_ENTRYPOINT} to {service}")
    dst = os.path.join(BUILD_PATH, "services", service, "service")
    shutil.copyfile(DOCKER_ENTRYPOINT_PATH, os.path.join(dst, DOCKER_ENTRYPOINT))
