import json, sys, os, netifaces, re, time, requests, threading, shutil
from jsonpath_ng.ext import parse
from os import environ
from multipledispatch import dispatch
from netaddr import *
import fileinput

filePath = None
saveFilePath = None
jsonValue = None

PRODUCT = os.environ["PRODUCT"] if environ.get("PRODUCT") else "onlyoffice"
BASE_DIR =  os.environ["BASE_DIR"] if environ.get("BASE_DIR") else  "/app/" + PRODUCT
ENV_EXTENSION = (os.environ.get("ENV_EXTENSION") or os.environ.get("INSTALLATION_TYPE")).lower() or "none"
PROXY_HOST = os.environ["PROXY_HOST"] if environ.get("PROXY_HOST") else "onlyoffice-proxy"
SERVICE_PORT = os.environ["SERVICE_PORT"] if environ.get("SERVICE_PORT") else "5050"
URLS = os.environ["URLS"] if environ.get("URLS") else "http://0.0.0.0:"
PATH_TO_CONF = os.environ["PATH_TO_CONF"] if environ.get("PATH_TO_CONF") else "/app/" + PRODUCT + "/config"
LOG_DIR = os.environ["LOG_DIR"] if environ.get("LOG_DIR") else "/var/log/" + PRODUCT
BUILD_PATH = os.environ["BUILD_PATH"] if environ.get("BUILD_PATH") else "/var/www"
NODE_CONTAINER_NAME = os.environ["NODE_CONTAINER_NAME"] if os.environ.get("NODE_CONTAINER_NAME") else "onlyoffice-node-services"
SERVICE_SOCKET_PORT = os.environ["SERVICE_SOCKET_PORT"] if os.environ.get("SERVICE_SOCKET_PORT") else SERVICE_PORT
SERVICE_SSOAUTH_PORT = os.environ["SERVICE_SSOAUTH_PORT"] if os.environ.get("SERVICE_SSOAUTH_PORT") else SERVICE_PORT
ROUTER_HOST = os.environ["ROUTER_HOST"] if environ.get("ROUTER_HOST") else "onlyoffice-router"
SOCKET_HOST = os.environ.get("NODE_CONTAINER_NAME") or os.environ.get("SOCKET_HOST") or "onlyoffice-socket"
MCP_ENDPOINT = os.environ.get("MCP_ENDPOINT") or os.environ.get("MCP_ENDPOINT") or "http://onlyoffice-mcp:5158/mcp"

MYSQL_CONTAINER_NAME = os.environ["MYSQL_CONTAINER_NAME"] if environ.get("MYSQL_CONTAINER_NAME") else "onlyoffice-mysql-server"
MYSQL_HOST = os.environ["MYSQL_HOST"] if environ.get("MYSQL_HOST") else None
MYSQL_PORT = os.environ["MYSQL_PORT"] if environ.get("MYSQL_PORT") else "3306"
MYSQL_DATABASE = os.environ["MYSQL_DATABASE"] if environ.get("MYSQL_DATABASE") else "onlyoffice"
MYSQL_USER = os.environ["MYSQL_USER"] if environ.get("MYSQL_USER") else "onlyoffice_user"
MYSQL_PASSWORD = os.environ["MYSQL_PASSWORD"] if environ.get("MYSQL_PASSWORD") else "onlyoffice_pass"
MYSQL_CONNECTION_HOST = MYSQL_HOST if MYSQL_HOST else MYSQL_CONTAINER_NAME

APP_CORE_SERVER_ROOT = os.environ["APP_CORE_SERVER_ROOT"] if environ.get("APP_CORE_SERVER_ROOT") else None
APP_CORE_BASE_DOMAIN = os.environ["APP_CORE_BASE_DOMAIN"] if environ.get("APP_CORE_BASE_DOMAIN") is not None else "localhost"
APP_CORE_MACHINEKEY = os.environ["APP_CORE_MACHINEKEY"] if environ.get("APP_CORE_MACHINEKEY") else "your_core_machinekey"
APP_URL_PORTAL = os.environ["APP_URL_PORTAL"] if environ.get("APP_URL_PORTAL") else "http://" + ROUTER_HOST + ":8092"
OAUTH_REDIRECT_URL = os.environ["OAUTH_REDIRECT_URL"] if environ.get("OAUTH_REDIRECT_URL") else None
APP_STORAGE_ROOT = os.environ["APP_STORAGE_ROOT"] if environ.get("APP_STORAGE_ROOT") else BASE_DIR + "/data/"
APP_KNOWN_PROXIES = os.environ["APP_KNOWN_PROXIES"]
APP_KNOWN_NETWORKS = os.environ["APP_KNOWN_NETWORKS"]
LOG_LEVEL = os.environ["LOG_LEVEL"].lower() if environ.get("LOG_LEVEL") else None
DEBUG_INFO = os.environ["DEBUG_INFO"] if environ.get("DEBUG_INFO") else "false"
SAMESITE = os.environ["SAMESITE"] if environ.get("SAMESITE") else "None"
DISABLE_VALIDATE_TOKEN = os.environ["DISABLE_VALIDATE_TOKEN"] if environ.get("DISABLE_VALIDATE_TOKEN") else "false"

CERTIFICATE_PATH = os.environ.get("CERTIFICATE_PATH")
CERTIFICATE_PARAM = "NODE_EXTRA_CA_CERTS=" + CERTIFICATE_PATH + " " if CERTIFICATE_PATH and os.path.exists(CERTIFICATE_PATH) else ""
TLS_REJECT_UNAUTHORIZED = "NODE_TLS_REJECT_UNAUTHORIZED=1" if os.getenv("NODE_TLS_REJECT_UNAUTHORIZED", "").lower() in ("1","true","enable") else "";

DOCUMENT_CONTAINER_NAME = os.environ["DOCUMENT_CONTAINER_NAME"] if environ.get("DOCUMENT_CONTAINER_NAME") else "onlyoffice-document-server"
DOCUMENT_SERVER_JWT_SECRET = os.environ["DOCUMENT_SERVER_JWT_SECRET"] if environ.get("DOCUMENT_SERVER_JWT_SECRET") else "your_jwt_secret"
DOCUMENT_SERVER_JWT_HEADER = os.environ["DOCUMENT_SERVER_JWT_HEADER"] if environ.get("DOCUMENT_SERVER_JWT_HEADER") else "AuthorizationJwt"
DOCUMENT_SERVER_URL_INTERNAL = os.environ["DOCUMENT_SERVER_URL_INTERNAL"] if environ.get("DOCUMENT_SERVER_URL_INTERNAL") else "http://" + DOCUMENT_CONTAINER_NAME + "/"
DOCUMENT_SERVER_URL_EXTERNAL = os.environ["DOCUMENT_SERVER_URL_EXTERNAL"] if environ.get("DOCUMENT_SERVER_URL_EXTERNAL") else None
DOCUMENT_SERVER_URL_PUBLIC = DOCUMENT_SERVER_URL_EXTERNAL if DOCUMENT_SERVER_URL_EXTERNAL else os.environ["DOCUMENT_SERVER_URL_PUBLIC"] if environ.get("DOCUMENT_SERVER_URL_PUBLIC") else "/ds-vpath/"
DOCUMENT_SERVER_CONNECTION_HOST = DOCUMENT_SERVER_URL_EXTERNAL if DOCUMENT_SERVER_URL_EXTERNAL else DOCUMENT_SERVER_URL_INTERNAL

ELK_CONTAINER_NAME = os.environ["ELK_CONTAINER_NAME"] if environ.get("ELK_CONTAINER_NAME") else "onlyoffice-opensearch"
ELK_SCHEME = os.environ["ELK_SCHEME"] if environ.get("ELK_SCHEME") else "http"
ELK_HOST = os.environ["ELK_HOST"] if environ.get("ELK_HOST") else None
ELK_PORT = os.environ["ELK_PORT"] if environ.get("ELK_PORT") else "9200"
ELK_THREADS = os.environ["ELK_THREADS"] if environ.get("ELK_THREADS") else "1"
ELK_CONNECTION_HOST = ELK_HOST if ELK_HOST else ELK_CONTAINER_NAME

RUN_FILE = sys.argv[1] if (len(sys.argv) > 1) else "none"
LOG_FILE = sys.argv[2] if (len(sys.argv) > 2) else "none"
CORE_EVENT_BUS = sys.argv[3] if (len(sys.argv) > 3) else ""

REDIS_CONTAINER_NAME = os.environ["REDIS_CONTAINER_NAME"] if environ.get("REDIS_CONTAINER_NAME") else "onlyoffice-redis"
REDIS_HOST = os.environ["REDIS_HOST"] if environ.get("REDIS_HOST") else None
REDIS_PORT = os.environ["REDIS_PORT"] if environ.get("REDIS_PORT") else "6379"
REDIS_USER_NAME = {"User": os.environ["REDIS_USER_NAME"]} if environ.get("REDIS_USER_NAME") else None
REDIS_PASSWORD = {"Password": os.environ["REDIS_PASSWORD"]} if environ.get("REDIS_PASSWORD") else None
REDIS_CONNECTION_HOST = REDIS_HOST if REDIS_HOST else REDIS_CONTAINER_NAME
REDIS_DB = os.environ["REDIS_DB"] if environ.get("REDIS_DB") else 0

RABBIT_CONTAINER_NAME = os.environ["RABBIT_CONTAINER_NAME"] if environ.get("RABBIT_CONTAINER_NAME") else "onlyoffice-rabbitmq"
RABBIT_PROTOCOL = os.environ["RABBIT_PROTOCOL"] if environ.get("RABBIT_PROTOCOL") else "amqp"
RABBIT_HOST = os.environ["RABBIT_HOST"] if environ.get("RABBIT_HOST") else None
RABBIT_USER_NAME = os.environ["RABBIT_USER_NAME"] if environ.get("RABBIT_USER_NAME") else "guest"
RABBIT_PASSWORD = os.environ["RABBIT_PASSWORD"] if environ.get("RABBIT_PASSWORD") else "guest"
RABBIT_PORT =  os.environ["RABBIT_PORT"] if environ.get("RABBIT_PORT") else "5672"
RABBIT_VIRTUAL_HOST = os.environ["RABBIT_VIRTUAL_HOST"] if environ.get("RABBIT_VIRTUAL_HOST") else "/"
RABBIT_CONNECTION_HOST = RABBIT_HOST if RABBIT_HOST else RABBIT_CONTAINER_NAME
RABBIT_URI = (
    {"Uri": os.environ["RABBIT_URI"]} if os.environ.get("RABBIT_URI")
    else {"Uri": f"{RABBIT_PROTOCOL}://{RABBIT_USER_NAME}:{RABBIT_PASSWORD}@{RABBIT_HOST}:{RABBIT_PORT}{RABBIT_VIRTUAL_HOST}"}
    if RABBIT_PROTOCOL == "amqps" and RABBIT_HOST else None
)

class RunServices:
    def __init__(self, SERVICE_PORT, PATH_TO_CONF):
        self.SERVICE_PORT = SERVICE_PORT
        self.PATH_TO_CONF = PATH_TO_CONF
    @dispatch(str)    
    def RunService(self, RUN_FILE):
        os.system(TLS_REJECT_UNAUTHORIZED + CERTIFICATE_PARAM + "node " + RUN_FILE + " --app.port=" + self.SERVICE_PORT +\
             " --app.appsettings=" + self.PATH_TO_CONF)
        return 1
        
    @dispatch(str, str)
    def RunService(self, RUN_FILE, ENV_EXTENSION):
        if sys.argv[1] == "supervisord":
            os.execvp(sys.argv[1], sys.argv[1:])
            return 1

        if ENV_EXTENSION == "none":
            self.RunService(RUN_FILE)
        os.system(TLS_REJECT_UNAUTHORIZED + CERTIFICATE_PARAM + "node " + RUN_FILE + " --app.port=" + self.SERVICE_PORT +\
             " --app.appsettings=" + self.PATH_TO_CONF +\
                " --app.environment=" + ENV_EXTENSION)
        return 1

    @dispatch(str, str, str)
    def RunService(self, RUN_FILE, ENV_EXTENSION, LOG_FILE):
        data = RUN_FILE.split(".")
        if data[-1] != "dll":
            self.RunService(RUN_FILE, ENV_EXTENSION)
        elif  ENV_EXTENSION == "none":
            os.system("dotnet " + RUN_FILE + " --urls=" + URLS + self.SERVICE_PORT +\
                " --\'$STORAGE_ROOT\'=" + APP_STORAGE_ROOT +\
                    " --pathToConf=" + self.PATH_TO_CONF +\
                        " --log:dir=" + LOG_DIR +\
                            " --log:name=" + LOG_FILE +\
                                " core:products:folder=/var/www/products/" +\
                                    " core:products:subfolder=server" + " " +\
                                        CORE_EVENT_BUS)
        else:
            os.system("dotnet " + RUN_FILE + " --urls=" + URLS + self.SERVICE_PORT +\
                 " --\'$STORAGE_ROOT\'=" + APP_STORAGE_ROOT +\
                    " --pathToConf=" + self.PATH_TO_CONF +\
                        " --log:dir=" + LOG_DIR +\
                            " --log:name=" + LOG_FILE +\
                                " --ENVIRONMENT=" + ENV_EXTENSION +\
                                    " core:products:folder=/var/www/products/" +\
                                        " core:products:subfolder=server" + " " +\
                                            CORE_EVENT_BUS)

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

def waitForHostAvailable(HOST_URL, TIMEOUT=10, INTERVAL=3, MAX_RETRIES=5, RETRY_INTERVAL=15):
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

    LOG_PRIORITY = dict(CRITICAL=0, ERROR=1, WARNING=2, INFORMATION=3, DEBUG=4, TRACE=5)
    CURRENT_PRIORITY = LOG_PRIORITY.get((os.getenv("LOG_LEVEL") or "INFORMATION").upper(), 3)

    def LOG(LEVEL, MESSAGE):
        if LOG_PRIORITY.get(LEVEL, 3) <= CURRENT_PRIORITY:
            print(f"[{LEVEL}] {MESSAGE}", flush=True)

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
    LOG_PRIORITY = dict(CRITICAL=0, ERROR=1, WARNING=2, INFORMATION=3, DEBUG=4, TRACE=5)
    CURRENT_PRIORITY = LOG_PRIORITY.get((os.getenv("LOG_LEVEL") or "INFORMATION").upper(), 3)

    def LOG(LEVEL, MESSAGE):
        if LOG_PRIORITY.get(LEVEL, 3) <= CURRENT_PRIORITY:
            print(f"[{LEVEL}] {MESSAGE}", flush=True)

    LOG("INFORMATION", "Plugins maintenance started...")

    os.makedirs(USER_PLUGINS_DIR, exist_ok=True)

    INSTALLED_PLUGINS = {}
    if os.path.exists(USER_STATE_FILE):
        for LINE in open(USER_STATE_FILE):
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
                CONFIG = json.load(open(CONFIG_PATH))
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

def check_docs_connection():
    filePath = "/app/onlyoffice/config/appsettings.json"
    jsonData = openJsonFile(filePath)

    updateJsonData(jsonData, "$.files.docservice.url.portal", APP_URL_PORTAL)
    updateJsonData(jsonData, "$.files.docservice.url.public", DOCUMENT_SERVER_URL_PUBLIC)
    updateJsonData(jsonData, "$.files.docservice.url.internal", DOCUMENT_SERVER_CONNECTION_HOST)
    updateJsonData(jsonData, "$.files.docservice.secret.value", DOCUMENT_SERVER_JWT_SECRET)
    updateJsonData(jsonData, "$.files.docservice.secret.header", DOCUMENT_SERVER_JWT_HEADER)

    if not waitForHostAvailable(DOCUMENT_SERVER_CONNECTION_HOST, TIMEOUT=10, INTERVAL=3, MAX_RETRIES=5, RETRY_INTERVAL=15):
        deleteJsonPath(jsonData, "$.files.docservice")

    writeJsonFile(filePath, jsonData)

#filePath = sys.argv[1]
saveFilePath = filePath
#jsonValue = sys.argv[2]

filePath = "/app/onlyoffice/config/appsettings.json"
jsonData = openJsonFile(filePath)
#jsonUpdateValue = parseJsonValue(jsonValue)
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

ip_address = netifaces.ifaddresses('eth0').get(netifaces.AF_INET)[0].get('addr')
netmask = netifaces.ifaddresses('eth0').get(netifaces.AF_INET)[0].get('netmask')
ip_address_netmask = '%s/%s' % (ip_address, netmask)
interface_cidr = IPNetwork(ip_address_netmask)
knownNetwork = [str(interface_cidr)]
knownProxies = ["127.0.0.1"]

if APP_KNOWN_NETWORKS:
    knownNetwork= knownNetwork + [x.strip() for x in APP_KNOWN_NETWORKS.split(',')]

if APP_KNOWN_PROXIES:
    knownNetwork= knownNetwork + [x.strip() for x in APP_KNOWN_PROXIES.split(',')]

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
    NLOG_PATH = "/app/onlyoffice/config/nlog.config"
    with open(NLOG_PATH) as f: NLOG = f.read()
    NLOG = re.sub(r'^(?!.*ZiggyCreatures)(.*minlevel=")\w+(")', rf'\1{LOG_LEVEL}\2', NLOG, flags=re.M)
    open(NLOG_PATH, "w").write(NLOG)

RELEASE_PLUGINS_DIR = "/var/www/studio/plugins/"
USER_PLUGINS_DIR = "/app/onlyoffice/data/Studio/webplugins/"
USER_STATE_FILE = USER_PLUGINS_DIR + ".plugins.state"

if os.path.isdir(RELEASE_PLUGINS_DIR):
    maintain_plugins()

threading.Thread(target=check_docs_connection, daemon=True).start()

run = RunServices(SERVICE_PORT, PATH_TO_CONF)
run.RunService(RUN_FILE, ENV_EXTENSION, LOG_FILE)