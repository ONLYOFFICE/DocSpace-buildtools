import json, sys, os, re, time, requests, threading, shutil, fileinput, subprocess
from jsonpath_ng.ext import parse
from netaddr import IPNetwork

def require_env(name):
    return os.environ.get(name) or (_ for _ in ()).throw(RuntimeError(f"{name} must be set"))

PRODUCT = os.environ.get("PRODUCT") or "onlyoffice"
BASE_DIR =  os.environ.get("BASE_DIR") or  "/app/" + PRODUCT
ENV_EXTENSION = (os.environ.get("ENV_EXTENSION") or os.environ.get("INSTALLATION_TYPE")).lower() or "none"
PROXY_HOST = os.environ.get("PROXY_HOST") or "onlyoffice-proxy"
SERVICE_PORT = os.environ.get("SERVICE_PORT") or "5050"
URLS = os.environ.get("URLS") or "http://0.0.0.0:"
PATH_TO_CONF = os.environ.get("PATH_TO_CONF") or "/app/" + PRODUCT + "/config"
LOG_DIR = os.environ.get("LOG_DIR") or "/var/log/" + PRODUCT
BUILD_PATH = os.environ.get("BUILD_PATH") or "/var/www"
NODE_CONTAINER_NAME = os.environ.get("NODE_CONTAINER_NAME") or "onlyoffice-node-services"
SERVICE_SOCKET_PORT = os.environ.get("SERVICE_SOCKET_PORT") or SERVICE_PORT
SERVICE_SSOAUTH_PORT = os.environ.get("SERVICE_SSOAUTH_PORT") or SERVICE_PORT
ROUTER_HOST = os.environ.get("ROUTER_HOST") or "onlyoffice-router"
SOCKET_HOST = os.environ.get("NODE_CONTAINER_NAME") or os.environ.get("SOCKET_HOST") or "onlyoffice-socket"
MCP_ENDPOINT = os.environ.get("MCP_ENDPOINT") or "http://onlyoffice-mcp:5158/mcp"

MYSQL_CONTAINER_NAME = os.environ.get("MYSQL_CONTAINER_NAME") or "onlyoffice-mysql-server"
MYSQL_HOST = os.environ.get("MYSQL_HOST") or None
MYSQL_PORT = os.environ.get("MYSQL_PORT") or "3306"
MYSQL_DATABASE = os.environ.get("MYSQL_DATABASE") or "onlyoffice"
MYSQL_USER = os.environ.get("MYSQL_USER") or "onlyoffice_user"
MYSQL_PASSWORD = require_env("MYSQL_PASSWORD")
MYSQL_CONNECTION_HOST = MYSQL_HOST if MYSQL_HOST else MYSQL_CONTAINER_NAME

APP_CORE_SERVER_ROOT = os.environ.get("APP_CORE_SERVER_ROOT") or None
APP_CORE_BASE_DOMAIN = os.environ.get("APP_CORE_BASE_DOMAIN", "localhost")
APP_CORE_MACHINEKEY = require_env("APP_CORE_MACHINEKEY")
APP_URL_PORTAL = os.environ.get("APP_URL_PORTAL") or "http://" + ROUTER_HOST + ":8092"
OAUTH_REDIRECT_URL = os.environ.get("OAUTH_REDIRECT_URL") or None
APP_STORAGE_ROOT = os.environ.get("APP_STORAGE_ROOT") or BASE_DIR + "/data/"
APP_KNOWN_PROXIES = os.environ.get("APP_KNOWN_PROXIES", "")
APP_KNOWN_NETWORKS = os.environ.get("APP_KNOWN_NETWORKS", "")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "").lower() or None
DEBUG_INFO = os.environ.get("DEBUG_INFO") or "false"
SAMESITE = os.environ.get("SAMESITE") or "None"
DISABLE_VALIDATE_TOKEN = os.environ.get("DISABLE_VALIDATE_TOKEN") or "false"

CERTIFICATE_PATH = os.environ.get("CERTIFICATE_PATH")
CERTIFICATE_PARAM = "NODE_EXTRA_CA_CERTS=" + CERTIFICATE_PATH + " " if CERTIFICATE_PATH and os.path.exists(CERTIFICATE_PATH) else ""
TLS_REJECT_UNAUTHORIZED = "NODE_TLS_REJECT_UNAUTHORIZED=1" if os.getenv("NODE_TLS_REJECT_UNAUTHORIZED", "").lower() in ("1","true","enable") else "";

DOCUMENT_CONTAINER_NAME = os.environ.get("DOCUMENT_CONTAINER_NAME") or "onlyoffice-document-server"
DOCUMENT_SERVER_JWT_SECRET = require_env("DOCUMENT_SERVER_JWT_SECRET")
DOCUMENT_SERVER_JWT_HEADER = os.environ.get("DOCUMENT_SERVER_JWT_HEADER") or "AuthorizationJwt"
DOCUMENT_SERVER_URL_INTERNAL = os.environ.get("DOCUMENT_SERVER_URL_INTERNAL") or "http://" + DOCUMENT_CONTAINER_NAME + "/"
DOCUMENT_SERVER_URL_EXTERNAL = os.environ.get("DOCUMENT_SERVER_URL_EXTERNAL") or None
DOCUMENT_SERVER_URL_PUBLIC = DOCUMENT_SERVER_URL_EXTERNAL if DOCUMENT_SERVER_URL_EXTERNAL else os.environ.get("DOCUMENT_SERVER_URL_PUBLIC") or "/ds-vpath/"
DOCUMENT_SERVER_CONNECTION_HOST = DOCUMENT_SERVER_URL_EXTERNAL if DOCUMENT_SERVER_URL_EXTERNAL else DOCUMENT_SERVER_URL_INTERNAL
DOCUMENT_SERVER_REQUIRED = {"true": True, "false": False}.get(os.environ.get("DOCUMENT_SERVER_REQUIRED", "").lower())

ELK_CONTAINER_NAME = os.environ.get("ELK_CONTAINER_NAME") or "onlyoffice-opensearch"
ELK_SCHEME = os.environ.get("ELK_SCHEME") or "http"
ELK_HOST = os.environ.get("ELK_HOST") or None
ELK_PORT = os.environ.get("ELK_PORT") or "9200"
ELK_THREADS = os.environ.get("ELK_THREADS") or "1"
ELK_CONNECTION_HOST = ELK_HOST if ELK_HOST else ELK_CONTAINER_NAME

RUN_FILE = sys.argv[1] if (len(sys.argv) > 1) else "none"
LOG_FILE = sys.argv[2] if (len(sys.argv) > 2) else "none"
CORE_EVENT_BUS = sys.argv[3] if (len(sys.argv) > 3) else ""

REDIS_CONTAINER_NAME = os.environ.get("REDIS_CONTAINER_NAME") or "onlyoffice-redis"
REDIS_HOST = os.environ.get("REDIS_HOST") or None
REDIS_PORT = os.environ.get("REDIS_PORT") or "6379"
REDIS_USER_NAME = {"User": os.environ["REDIS_USER_NAME"]} if os.environ.get("REDIS_USER_NAME") else None
REDIS_PASSWORD = {"Password": os.environ["REDIS_PASSWORD"]} if os.environ.get("REDIS_PASSWORD") else None
REDIS_CONNECTION_HOST = REDIS_HOST if REDIS_HOST else REDIS_CONTAINER_NAME
REDIS_DB = os.environ.get("REDIS_DB") or 0
REDIS_SSL = {"true": True, "false": False}.get(os.environ.get("REDIS_SSL", "").lower())

RABBIT_CONTAINER_NAME = os.environ.get("RABBIT_CONTAINER_NAME") or "onlyoffice-rabbitmq"
RABBIT_PROTOCOL = os.environ.get("RABBIT_PROTOCOL") or "amqp"
RABBIT_HOST = os.environ.get("RABBIT_HOST") or None
RABBIT_USER_NAME = os.environ.get("RABBIT_USER_NAME") or "guest"
RABBIT_PASSWORD = require_env("RABBIT_PASSWORD")
RABBIT_PORT =  os.environ.get("RABBIT_PORT") or "5672"
RABBIT_VIRTUAL_HOST = os.environ.get("RABBIT_VIRTUAL_HOST") or "/"
RABBIT_CONNECTION_HOST = RABBIT_HOST if RABBIT_HOST else RABBIT_CONTAINER_NAME
RABBIT_URI = (
    {"Uri": os.environ["RABBIT_URI"]} if os.environ.get("RABBIT_URI")
    else {"Uri": f"{RABBIT_PROTOCOL}://{RABBIT_USER_NAME}:{RABBIT_PASSWORD}@{RABBIT_HOST}:{RABBIT_PORT}{RABBIT_VIRTUAL_HOST}"}
    if RABBIT_PROTOCOL == "amqps" and RABBIT_HOST else None
)

LOG_PRIORITY = dict(CRITICAL=0, ERROR=1, WARNING=2, INFORMATION=3, DEBUG=4, TRACE=5)
CURRENT_PRIORITY = LOG_PRIORITY.get((os.getenv("LOG_LEVEL") or "INFORMATION").upper(), 3)

def LOG(LEVEL, MESSAGE):
    if LOG_PRIORITY.get(LEVEL, 3) <= CURRENT_PRIORITY:
        print(f"[{LEVEL}] {MESSAGE}", flush=True)

class RunServices:
    def __init__(self, SERVICE_PORT, PATH_TO_CONF):
        self.SERVICE_PORT = SERVICE_PORT
        self.PATH_TO_CONF = PATH_TO_CONF

    def RunService(self, RUN_FILE, ENV_EXTENSION="none", LOG_FILE=None):
        if LOG_FILE and RUN_FILE.endswith(".dll"):
            cmd = (f"dotnet {RUN_FILE} --urls={URLS}{self.SERVICE_PORT} --'$STORAGE_ROOT'={APP_STORAGE_ROOT}"
                   f" --pathToConf={self.PATH_TO_CONF} --log:dir={LOG_DIR} --log:name={LOG_FILE}"
                   f" core:products:folder=/var/www/products/ core:products:subfolder=server {CORE_EVENT_BUS}")
            if ENV_EXTENSION != "none":
                cmd += f" --ENVIRONMENT={ENV_EXTENSION}"
        else:
            cmd = f"{TLS_REJECT_UNAUTHORIZED}{CERTIFICATE_PARAM}node {RUN_FILE} --app.port={self.SERVICE_PORT} --app.appsettings={self.PATH_TO_CONF}"
            if ENV_EXTENSION != "none":
                cmd += f" --app.environment={ENV_EXTENSION}"
        subprocess.call(cmd, shell=True)


def openJsonFile(filePath):
    try:
        with open(filePath, 'r') as f:
            return json.load(f)
    except FileNotFoundError as e:
        return False
    except IOError as e:
        return False

def parseJsonValue(jsonValue):
    data = jsonValue.split("=")
    data[0] = "$." + data[0].strip()
    data[1] = data[1].replace(" ", "")
    
    return data

def updateJsonData(jsonData, jsonKey, jsonUpdateValue):
    jsonpath_expr = parse(jsonKey)
    jsonpath_expr.find(jsonData)
    jsonpath_expr.update(jsonData, jsonUpdateValue)
    
    return jsonData

def writeJsonFile(jsonFile, jsonData, indent=4):
    with open(jsonFile, 'w') as f:
        f.write(json.dumps(jsonData, ensure_ascii=False, indent=indent))
    
    return 1

def deleteJsonPath(jsonData, jsonPath):
    expr = parse(jsonPath)
    matches = expr.find(jsonData)

    for match in matches:
        path = match.full_path
        context = jsonData
        parts = [p for p in str(path).split('.') if p]
        for key in parts[:-1]:
            context = context.get(key, {})
        last_key = parts[-1]
        if isinstance(context, dict) and last_key in context:
            del context[last_key]

    return jsonData

def waitForHostAvailable(HOST_URL, TIMEOUT=10, INTERVAL=3, MAX_RETRIES=5, RETRY_INTERVAL=30):
    """
    Check if HOST_URL is reachable.

    Args:
        HOST_URL (str): Host address (e.g. http://document-server:8083).
        TIMEOUT (int): Max seconds to wait in one attempt.
        INTERVAL (int): Delay between requests inside one attempt.
        MAX_RETRIES (int): Number of extra attempts if host is still unavailable.
        RETRY_INTERVAL (int): Delay between attempts.

    Returns:
        bool: True if host becomes available, otherwise False.
    """

    ATTEMPT = 0
    while True:
        ATTEMPT += 1
        LOG("INFORMATION", f"Waiting for host: {HOST_URL} (timeout: {TIMEOUT} seconds, attempt {ATTEMPT}/{MAX_RETRIES})")

        START_TIME = time.time()
        RESPONSE = None

        try:
            with requests.Session() as SESS:
                while time.time() - START_TIME < TIMEOUT:
                    try:
                        RESPONSE = SESS.head(HOST_URL, timeout=3, allow_redirects=True)
                        if RESPONSE is not None and not RESPONSE.ok:
                            RESPONSE = SESS.get(HOST_URL, timeout=3, allow_redirects=True, stream=True)
                            try:
                                RESPONSE.close()
                            except Exception:
                                pass

                        if RESPONSE is not None and RESPONSE.ok:
                            LOG("INFORMATION", f"Host is available: {HOST_URL} ({RESPONSE.status_code})")
                            return True

                        if RESPONSE is not None:
                            LOG("WARNING", f"Received status {RESPONSE.status_code} from {HOST_URL}")
                        else:
                            LOG("WARNING", f"No response from {HOST_URL}")

                    except requests.RequestException as e:
                        LOG("DEBUG", f"Connection error to {HOST_URL}: {e}")
                    except Exception as e:
                        LOG("CRITICAL", f"Unexpected error in waitForHostAvailable: {e}")

                    time.sleep(INTERVAL)
        except Exception as e:
            LOG("CRITICAL", f"Unexpected error creating session: {e}")

        if ATTEMPT < MAX_RETRIES:
            LOG("WARNING", f"{HOST_URL} is not available yet, retrying in {RETRY_INTERVAL} seconds...")
            time.sleep(RETRY_INTERVAL)
        else:
            LOG("ERROR", f"{HOST_URL} is not available after {MAX_RETRIES} attempts {f' ({RESPONSE.status_code})' if RESPONSE else ''}")
            return False

def maintain_plugins():
    LOG("INFORMATION", "Plugins maintenance started...")

    os.makedirs(USER_PLUGINS_DIR, exist_ok=True)

    INSTALLED_PLUGINS = {}
    if os.path.exists(USER_STATE_FILE):
        with open(USER_STATE_FILE) as f:
            for LINE in f:
                PARTS = LINE.strip().split()
                if len(PARTS) == 2:
                    INSTALLED_PLUGINS[PARTS[0]] = PARTS[1]
                else:
                    LOG("error", f"Invalid line in {USER_STATE_FILE}: '{LINE.strip()}'")

    LOG("DEBUG", f"Loaded installed plugins: {INSTALLED_PLUGINS}")

    RELEASE_PLUGINS = {}
    for PLUGIN in os.listdir(RELEASE_PLUGINS_DIR):
        CONFIG_PATH = f"{RELEASE_PLUGINS_DIR}{PLUGIN}/config.json"
        if os.path.exists(CONFIG_PATH):
            try:
                with open(CONFIG_PATH) as f:
                    CONFIG = json.load(f)
                VERSION = CONFIG.get("version")
                RELEASE_PLUGINS[PLUGIN] = VERSION
            except Exception as e:
                LOG("error", f"Failed to parse {CONFIG_PATH}: {e}")

    LOG("DEBUG", f"Release plugins summary: {RELEASE_PLUGINS}")

    ANY_INSTALLED = ANY_UPDATED = False

    for PLUGIN, RELEASE_VERSION in RELEASE_PLUGINS.items():
        USER_DIR = f"{USER_PLUGINS_DIR}{PLUGIN}"
        RELEASE_DIR = f"{RELEASE_PLUGINS_DIR}{PLUGIN}"

        LOG("DEBUG", f"Processing {PLUGIN}: release={RELEASE_VERSION}, installed={INSTALLED_PLUGINS.get(PLUGIN)}")

        if PLUGIN in INSTALLED_PLUGINS:
            if not os.path.isdir(USER_DIR):
                LOG("INFORMATION", f"Removed by user: {PLUGIN}")
                continue

            if INSTALLED_PLUGINS[PLUGIN] != RELEASE_VERSION:
                ANY_UPDATED = True
                LOG("INFORMATION", f"Updating {PLUGIN}: {INSTALLED_PLUGINS[PLUGIN]} -> {RELEASE_VERSION}")
                try:
                    shutil.rmtree(USER_DIR)
                    shutil.copytree(RELEASE_DIR, USER_DIR)
                    INSTALLED_PLUGINS[PLUGIN] = RELEASE_VERSION
                except Exception as e:
                    LOG("ERROR", f"Failed to update {PLUGIN}: {e}")
            else:
                LOG("DEBUG", f"No update needed for {PLUGIN}")
        else:
            if os.path.exists(USER_DIR):
                LOG("DEBUG", f"Cleaning orphan directory {USER_DIR}")
                try:
                    shutil.rmtree(USER_DIR)
                except Exception as e:
                    LOG("ERROR", f"Failed to cleanup {PLUGIN}: {e}")
                    continue

            ANY_INSTALLED = True
            LOG("INFORMATION", f"Installing new plugin: {PLUGIN}")
            try:
                shutil.copytree(RELEASE_DIR, USER_DIR)
                INSTALLED_PLUGINS[PLUGIN] = RELEASE_VERSION
            except Exception as e:
                LOG("ERROR", f"Failed to install {PLUGIN}: {e}")

    try:
        with open(USER_STATE_FILE, "w") as FILE:
            FILE.write("\n".join(f"{PLUGIN} {VERSION}" for PLUGIN, VERSION in INSTALLED_PLUGINS.items()))
        LOG("DEBUG", f"Plugins state saved to {USER_STATE_FILE}")
    except Exception as e:
        LOG("DEBUG", f"Failed to write {USER_STATE_FILE}: {e}")

    RESULT = (ANY_INSTALLED and "Plugins installed successfully." or ANY_UPDATED and "Plugins updated successfully." or "Plugins are up to date.")
    LOG("INFORMATION", RESULT)

def check_docs_connection(wait=True):
    filePath = "/app/onlyoffice/config/appsettings.json"
    jsonData = openJsonFile(filePath)

    updateJsonData(jsonData, "$.files.docservice.url.portal", APP_URL_PORTAL)
    updateJsonData(jsonData, "$.files.docservice.url.public", DOCUMENT_SERVER_URL_PUBLIC)
    updateJsonData(jsonData, "$.files.docservice.url.internal", DOCUMENT_SERVER_CONNECTION_HOST)
    updateJsonData(jsonData, "$.files.docservice.secret.value", DOCUMENT_SERVER_JWT_SECRET)
    updateJsonData(jsonData, "$.files.docservice.secret.header", DOCUMENT_SERVER_JWT_HEADER)

    if DOCUMENT_SERVER_REQUIRED is False:
        deleteJsonPath(jsonData, "$.files.docservice")
    elif wait and not waitForHostAvailable(DOCUMENT_SERVER_CONNECTION_HOST, TIMEOUT=10, INTERVAL=3, MAX_RETRIES=5, RETRY_INTERVAL=15):
        if DOCUMENT_SERVER_REQUIRED is None:
            deleteJsonPath(jsonData, "$.files.docservice")
        else:
            LOG("WARNING", f"{DOCUMENT_SERVER_CONNECTION_HOST} did not become available within the timeout; keeping $.files.docservice in config (DOCUMENT_SERVER_REQUIRED=true)")

    writeJsonFile(filePath, jsonData)


filePath = "/app/onlyoffice/config/appsettings.json"
jsonData = openJsonFile(filePath)
updateJsonData(jsonData,"$.ConnectionStrings.default.connectionString", "Server="+ MYSQL_CONNECTION_HOST +";Port="+ MYSQL_PORT +";Database="+ MYSQL_DATABASE +";User ID="+ MYSQL_USER +";Password="+ MYSQL_PASSWORD +";Pooling=true;Character Set=utf8;AutoEnlist=false;SSL Mode=none;ConnectionReset=false;AllowPublicKeyRetrieval=true",)
updateJsonData(jsonData,"$.core.server-root", APP_CORE_SERVER_ROOT)
updateJsonData(jsonData,"$.core.base-domain", APP_CORE_BASE_DOMAIN)
updateJsonData(jsonData,"$.core.machinekey", APP_CORE_MACHINEKEY)
updateJsonData(jsonData,"$.core.products.subfolder", "server")
updateJsonData(jsonData,"$.core.notify.postman", "services")
updateJsonData(jsonData,"$.web.hub.internal", "http://" + SOCKET_HOST + ":" + SERVICE_SOCKET_PORT + "/")
updateJsonData(jsonData,"$.core.oidc.disableValidateToken", DISABLE_VALIDATE_TOKEN)
updateJsonData(jsonData,"$.core.oidc.showPII", DEBUG_INFO)
updateJsonData(jsonData,"$.debug-info.enabled", DEBUG_INFO)
updateJsonData(jsonData,"$.web.samesite", SAMESITE)

if MCP_ENDPOINT:
    updateJsonData(jsonData, "$.ai.mcp.[0].endpoint", MCP_ENDPOINT)

_ip_match = re.search(r'inet (\S+)', subprocess.check_output(['ip', '-4', '-o', 'addr', 'show', 'scope', 'global'], text=True))
iface_cidr = _ip_match.group(1) if _ip_match else "127.0.0.1/8"
knownNetwork = [str(IPNetwork(iface_cidr).cidr)]
knownProxies = ["127.0.0.1"]

if APP_KNOWN_NETWORKS:
    knownNetwork= knownNetwork + [x.strip() for x in APP_KNOWN_NETWORKS.split(',')]

if APP_KNOWN_PROXIES:
    knownProxies = knownProxies + [x.strip() for x in APP_KNOWN_PROXIES.split(',')]

updateJsonData(jsonData,"$.core.hosting.forwardedHeadersOptions.knownNetworks", knownNetwork)
updateJsonData(jsonData,"$.core.hosting.forwardedHeadersOptions.knownProxies", knownProxies)

writeJsonFile(filePath, jsonData)

filePath = "/app/onlyoffice/config/apisystem.json"
jsonData = openJsonFile(filePath)
updateJsonData(jsonData, "$.ConnectionStrings.default.connectionString", "Server="+ MYSQL_CONNECTION_HOST +";Port=3306;Database="+ MYSQL_DATABASE +";User ID="+ MYSQL_USER +";Password="+ MYSQL_PASSWORD +";Pooling=true;Character Set=utf8;AutoEnlist=false;SSL Mode=none;ConnectionReset=false;AllowPublicKeyRetrieval=true",)
updateJsonData(jsonData,"$.core.base-domain", APP_CORE_BASE_DOMAIN)
updateJsonData(jsonData,"$.core.machinekey", APP_CORE_MACHINEKEY)
writeJsonFile(filePath, jsonData)

filePath = "/app/onlyoffice/config/appsettings.services.json"
jsonData = openJsonFile(filePath)
updateJsonData(jsonData,"$.logPath", LOG_DIR)
updateJsonData(jsonData,"$.logLevel", LOG_LEVEL)
writeJsonFile(filePath, jsonData)

if OAUTH_REDIRECT_URL:
    filePath = "/app/onlyoffice/config/autofac.consumers.json"
    jsonData = openJsonFile(filePath)
    
    for component in jsonData['components']:
        if 'parameters' in component and 'additional' in component['parameters']:
            for key, value in component['parameters']['additional'].items():
                if ( re.search(r'.*RedirectUrl$', key)  and key != "weixinRedirectUrl" and value): 
                    component['parameters']['additional'][key] = OAUTH_REDIRECT_URL
                    
    writeJsonFile(filePath, jsonData)

if ENV_EXTENSION != "dev":
    filePath = "/app/onlyoffice/config/elastic.json"
    jsonData = openJsonFile(filePath)
    jsonData["elastic"]["Scheme"] = ELK_SCHEME
    jsonData["elastic"]["Host"] = ELK_CONNECTION_HOST
    jsonData["elastic"]["Port"] = ELK_PORT
    jsonData["elastic"]["Threads"] = ELK_THREADS
    writeJsonFile(filePath, jsonData)

filePath = "/app/onlyoffice/config/socket.json"
jsonData = openJsonFile(filePath)
updateJsonData(jsonData,"$.socket.port", SERVICE_SOCKET_PORT)
writeJsonFile(filePath, jsonData)

filePath = "/app/onlyoffice/config/ssoauth.json"
jsonData = openJsonFile(filePath)
updateJsonData(jsonData,"$.ssoauth.port", SERVICE_SSOAUTH_PORT)
writeJsonFile(filePath, jsonData)

filePath = "/app/onlyoffice/config/rabbitmq.json"
jsonData = openJsonFile(filePath)
updateJsonData(jsonData,"$.RabbitMQ.Hostname", RABBIT_CONNECTION_HOST)
updateJsonData(jsonData,"$.RabbitMQ.UserName", RABBIT_USER_NAME)
updateJsonData(jsonData, "$.RabbitMQ.Password", RABBIT_PASSWORD)
updateJsonData(jsonData, "$.RabbitMQ.Port", RABBIT_PORT)
updateJsonData(jsonData, "$.RabbitMQ.VirtualHost", RABBIT_VIRTUAL_HOST)
jsonData["RabbitMQ"].update(RABBIT_URI) if RABBIT_URI is not None else None
writeJsonFile(filePath, jsonData)

filePath = "/app/onlyoffice/config/redis.json"
jsonData = openJsonFile(filePath)
updateJsonData(jsonData,"$.Redis.Hosts.[0].Host", REDIS_CONNECTION_HOST)
updateJsonData(jsonData,"$.Redis.Hosts.[0].Port", REDIS_PORT)
updateJsonData(jsonData,"$.Redis.Database", REDIS_DB)
jsonData["Redis"].update(REDIS_USER_NAME) if REDIS_USER_NAME is not None else None
jsonData["Redis"].update(REDIS_PASSWORD) if REDIS_PASSWORD is not None else None
updateJsonData(jsonData, "$.Redis.Ssl", REDIS_SSL) if REDIS_SSL is not None else None
writeJsonFile(filePath, jsonData)

filePath = os.path.join(BUILD_PATH, "services", "ASC.Migration.Runner", "service", "appsettings.runner.json")
if os.path.isfile(filePath):
    jsonData = openJsonFile(filePath)
    conn_str = f"Server={MYSQL_CONNECTION_HOST};Database={MYSQL_DATABASE};User ID={MYSQL_USER};Password={MYSQL_PASSWORD};Command Timeout=100"
    updateJsonData(jsonData, "$.options.Providers[0].ConnectionString", conn_str)
    updateJsonData(jsonData, "$.options.TeamlabsiteProviders[0].ConnectionString", conn_str)
    writeJsonFile(filePath, jsonData)

filePath = os.path.join(BUILD_PATH, "services", "ASC.Web.HealthChecks.UI", "service", "appsettings.json")
if os.path.isfile(filePath):
    for line in fileinput.input(filePath, inplace=True):
        line = line.replace("localhost:9899", f"{NODE_CONTAINER_NAME}:{SERVICE_SOCKET_PORT}")
        line = line.replace("localhost:9834", f"{NODE_CONTAINER_NAME}:{SERVICE_SSOAUTH_PORT}")
        sys.stdout.write(line)

if LOG_LEVEL:
    try:
        with open("/etc/supervisor/conf.d/supervisord.conf") as f:
            IS_DOTNET_SUPERVISOR = RUN_FILE == "supervisord" and "command=dotnet" in f.read()
    except OSError:
        IS_DOTNET_SUPERVISOR = False
    if RUN_FILE.endswith(".dll") or IS_DOTNET_SUPERVISOR:
        NLOG_PATH = "/app/onlyoffice/config/nlog.config"
        try:
            with open(NLOG_PATH) as f: NLOG = f.read()
            NLOG = re.sub(r'^(?!.*ZiggyCreatures)(.*minlevel=")\w+(")', rf'\1{LOG_LEVEL}\2', NLOG, flags=re.M)
            with open(NLOG_PATH, "w") as f: f.write(NLOG)
        except OSError:
            LOG("WARNING", f"{NLOG_PATH} is read-only, skipping LOG_LEVEL patch")

RELEASE_PLUGINS_DIR = "/var/www/studio/plugins/"
USER_PLUGINS_DIR = "/app/onlyoffice/data/Studio/webplugins/"
USER_STATE_FILE = USER_PLUGINS_DIR + ".plugins.state"

if os.path.isdir(RELEASE_PLUGINS_DIR):
    maintain_plugins()

if sys.argv[1] == "supervisord":
    check_docs_connection(wait=False)
    os.execvp(sys.argv[1], sys.argv[1:])

threading.Thread(target=check_docs_connection, daemon=True).start()

run = RunServices(SERVICE_PORT, PATH_TO_CONF)
run.RunService(RUN_FILE, ENV_EXTENSION, LOG_FILE)