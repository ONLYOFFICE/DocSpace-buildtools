import os
import socket
import sys
import time
from xmlrpc.client import Fault
from supervisor import childutils

RUNNER = "ASC.Migration.Runner"
MYSQL_HOST = os.environ.get("MYSQL_HOST") or os.environ.get("MYSQL_CONTAINER_NAME") or "onlyoffice-mysql-server"
MYSQL_PORT = int(os.environ.get("MYSQL_PORT") or 3306)
MYSQL_WAIT_TIMEOUT = 300
# Slows down the Docker restart loop when the migration itself is broken
RESTART_DELAY = 30

rpc = childutils.getRPCInterface(os.environ)


def log(message):
    print(f"[start-after-migration] {message}", file=sys.stderr, flush=True)


def wait_for_mysql():
    deadline = time.monotonic() + MYSQL_WAIT_TIMEOUT
    while time.monotonic() < deadline:
        try:
            socket.create_connection((MYSQL_HOST, MYSQL_PORT), timeout=5).close()
            log("MySQL is reachable.")
            return
        except OSError:
            time.sleep(2)
    log(f"MySQL is still unreachable after {MYSQL_WAIT_TIMEOUT}s, running the migration anyway.")


def start_services():
    # "start all" would also relaunch the exited runner
    for process in rpc.supervisor.getAllProcessInfo():
        if process["name"] == RUNNER or process["statename"] != "STOPPED":
            continue
        name = f"{process['group']}:{process['name']}"
        try:
            rpc.supervisor.startProcess(name, False)
        except Fault as error:
            log(f"Could not start {name}: {error.faultString}")


# All containers start together on a host reboot or compose down/up, so MySQL may not be up yet
log(f"Waiting for MySQL at {MYSQL_HOST}:{MYSQL_PORT}...")
wait_for_mysql()
rpc.supervisor.startProcess(RUNNER, False)
services_started = False

while True:
    headers, payload = childutils.listener.wait(sys.stdin, sys.stdout)
    event = childutils.get_headers(payload)
    if event.get("processname") == RUNNER and not services_started:
        if event.get("expected") == "1":
            log("Migration succeeded, starting services...")
            start_services()
            services_started = True
            log("All services started.")
        else:
            log(f"Migration failed (pid {event.get('pid')}, exit status in supervisord_dotnet.log), "
                f"stopping the container in {RESTART_DELAY}s so that Docker restarts it.")
            time.sleep(RESTART_DELAY)
            rpc.supervisor.shutdown()
            break
    childutils.listener.ok(sys.stdout)
