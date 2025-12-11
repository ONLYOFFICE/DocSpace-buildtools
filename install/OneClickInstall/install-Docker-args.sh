#!/usr/bin/env bash

PACKAGE_SYSNAME="onlyoffice"
PRODUCT_NAME="DocSpace"
PRODUCT=$(tr '[:upper:]' '[:lower:]' <<< ${PRODUCT_NAME})
HELP_TARGET="install-Docker.sh"
OFFLINE_IMAGE_LOAD="false"

while [ "$1" != "" ]; do
    case "$1" in
        -u       | --update              ) [ -n "$2" ] && UPDATE=$2                                                               && shift ;;
        -reg     | --registry            ) [ -n "$2" ] && REGISTRY_URL=$2                                                         && shift ;;
        -un      | --username            ) [ -n "$2" ] && USERNAME=$2                                                             && shift ;;
        -p       | --password            ) [ -n "$2" ] && PASSWORD=$2                                                             && shift ;;
        -ids     | --installdocspace     ) [ -n "$2" ] && INSTALL_PRODUCT=$2                                                      && shift ;;
        -idocs   | --installdocs         ) [ -n "$2" ] && INSTALL_DOCUMENT_SERVER=$2                                              && shift ;;
        -imysql  | --installmysql        ) [ -n "$2" ] && INSTALL_MYSQL_SERVER=$2                                                 && shift ;;
        -irbt    | --installrabbitmq     ) [ -n "$2" ] && INSTALL_RABBITMQ=$2                                                     && shift ;;
        -irds    | --installredis        ) [ -n "$2" ] && INSTALL_REDIS=$2                                                        && shift ;;
        -ht      | --helptarget          ) [ -n "$2" ] && HELP_TARGET=$2                                                          && shift ;;
        -mysqld  | --mysqldatabase       ) [ -n "$2" ] && MYSQL_DATABASE=$2                                                       && shift ;;
        -mysqlrp | --mysqlrootpassword   ) [ -n "$2" ] && MYSQL_ROOT_PASSWORD=$2                                                  && shift ;;
        -mysqlu  | --mysqluser           ) [ -n "$2" ] && MYSQL_USER=$2                                                           && shift ;;
        -mysqlh  | --mysqlhost           ) [ -n "$2" ] && MYSQL_HOST=$2                                                           && shift ;;
        -mysqlport| --mysqlport          ) [ -n "$2" ] && MYSQL_PORT=$2                                                           && shift ;;
        -mysqlp  | --mysqlpassword       ) [ -n "$2" ] && MYSQL_PASSWORD=$2                                                       && shift ;;
        -espr    | --elasticprotocol     ) [ -n "$2" ] && ELK_SCHEME=$2                                                           && shift ;;
        -esh     | --elastichost         ) [ -n "$2" ] && ELK_HOST=$2                                                             && shift ;;
        -esp     | --elasticport         ) [ -n "$2" ] && ELK_PORT=$2                                                             && shift ;;
        -skiphc  | --skiphardwarecheck   ) [ -n "$2" ] && SKIP_HARDWARE_CHECK=$2                                                  && shift ;;
        -sm      | --stack-mode          ) [ -n "$2" ] && STACK_MODE=$2                                                           && shift ;;
        -ep      | --externalport        ) [ -n "$2" ] && EXTERNAL_PORT=$2                                                        && shift ;;
        -dsh     | --docspacehost        ) [ -n "$2" ] && APP_URL_PORTAL=$2                                                       && shift ;;
        -mk      | --machinekey          ) [ -n "$2" ] && APP_CORE_MACHINEKEY=$2                                                  && shift ;;
        -env     | --environment         ) [ -n "$2" ] && ENV_EXTENSION=$2                                                        && shift ;;
        -s       | --status              ) [ -n "$2" ] && STATUS=$2 && IMAGE_NAME="${PACKAGE_SYSNAME}/${STATUS}${PRODUCT}-api"    && shift ;;
        -dsv     | --docspaceversion     ) [ -n "$2" ] && DOCKER_TAG=$2                                                           && shift ;;
        -gb      | --gitbranch           ) [ -n "$2" ] && PARAMETERS="$PARAMETERS $1" && GIT_BRANCH=$2                            && shift ;;
        -docsi   | --docsimage           ) [ -n "$2" ] && DOCUMENT_SERVER_IMAGE_NAME=$2                                           && shift ;;
        -docsv   | --docsversion         ) [ -n "$2" ] && DOCUMENT_SERVER_VERSION=$2                                              && shift ;;
        -docsurl | --docsurl             ) [ -n "$2" ] && DOCUMENT_SERVER_URL_EXTERNAL=$2                                         && shift ;;
        -dbm     | --databasemigration   ) [ -n "$2" ] && DATABASE_MIGRATION=$2                                                   && shift ;;
        -jh      | --jwtheader           ) [ -n "$2" ] && DOCUMENT_SERVER_JWT_HEADER=$2                                           && shift ;;
        -js      | --jwtsecret           ) [ -n "$2" ] && DOCUMENT_SERVER_JWT_SECRET=$2                                           && shift ;;
        -it      | --installationtype | --installation_type ) [ -n "$2" ] && INSTALLATION_TYPE="${2^^}"                           && shift ;;
        -ms      | --makeswap            ) [ -n "$2" ] && MAKESWAP=$2                                                             && shift ;;
        -ies     | --installelastic      ) [ -n "$2" ] && INSTALL_ELASTICSEARCH=$2                                                && shift ;;
        -ifb     | --installfluentbit    ) [ -n "$2" ] && INSTALL_FLUENT_BIT=$2                                                   && shift ;;
        -rdsh    | --redishost           ) [ -n "$2" ] && REDIS_HOST=$2                                                           && shift ;;
        -rdsp    | --redisport           ) [ -n "$2" ] && REDIS_PORT=$2                                                           && shift ;;
        -rdsu    | --redisusername       ) [ -n "$2" ] && REDIS_USER_NAME=$2                                                      && shift ;;
        -rdspass | --redispassword       ) [ -n "$2" ] && REDIS_PASSWORD=$2                                                       && shift ;;
        -rbpr    | --rabbitmqprotocol    ) [ -n "$2" ] && RABBIT_PROTOCOL=$2                                                      && shift ;;
        -rbth    | --rabbitmqhost        ) [ -n "$2" ] && RABBIT_HOST=$2                                                          && shift ;;
        -rbtp    | --rabbitmqport        ) [ -n "$2" ] && RABBIT_PORT=$2                                                          && shift ;;
        -rbtu    | --rabbitmqusername    ) [ -n "$2" ] && RABBIT_USER_NAME=$2                                                     && shift ;;
        -rbtpass | --rabbitmqpassword    ) [ -n "$2" ] && RABBIT_PASSWORD=$2                                                      && shift ;;
        -rbtvh   | --rabbitmqvirtualhost ) [ -n "$2" ] && RABBIT_VIRTUAL_HOST=$2                                                  && shift ;;
        -led     | --letsencryptdomain | --certdomain ) [ -n "$2" ] && LETS_ENCRYPT_DOMAIN=$2                                     && shift ;;
        -lem     | --letsencryptmail     ) [ -n "$2" ] && LETS_ENCRYPT_MAIL=$2                                                    && shift ;;
        -du      | --dashboardsusername  ) [ -n "$2" ] && DASHBOARDS_USERNAME=$2                                                  && shift ;;
        -dp      | --dashboardspassword  ) [ -n "$2" ] && DASHBOARDS_PASSWORD=$2                                                  && shift ;;
        -noni    | --noninteractive      ) [ -n "$2" ] && NON_INTERACTIVE=$2                                                      && shift ;;
        -uni     | --uninstall           ) [ -n "$2" ] && UNINSTALL=$2 && [ "$UNINSTALL" = "true" ] && OFFLINE_IMAGE_LOAD="true"  && shift ;;
        -off     | --offline             ) [ -n "$2" ] && OFFLINE_INSTALLATION=$2                                                 && shift ;;
        -eh      | --extrahosts          ) [ -n "$2" ] && EXTRA_HOSTS=$2                                                          && shift ;;
        -ls      | --localscripts        )                                                                                           shift ;;
        -vd      | --volumesdir          )
            [ -n "$2" ] && VOLUMES_DIR="$2"
            [[ "$VOLUMES_DIR" != /* ]] && VOLUMES_DIR="$(cd "$(dirname "$VOLUMES_DIR")" && pwd)/$(basename "$VOLUMES_DIR")"
            [ -d "$VOLUMES_DIR" ] || { echo "Error: Volumes directory not found: ${VOLUMES_DIR}" >&2; exit 1; }
            [[ "$VOLUMES_DIR" == "$BASE_DIR"* ]] && { echo "Warning: Please change the volumes directory, as $BASE_DIR will be removed during an update."; exit 1; }
            shift
        ;;
        -cf      | --certfile            )
            [ -n "$2" ] && CERTIFICATE_PATH="$2"
            [[ "$CERTIFICATE_PATH" != /* ]] && CERTIFICATE_PATH="$(cd "$(dirname "$CERTIFICATE_PATH")" && pwd)/$(basename "$CERTIFICATE_PATH")"
            [ -f "$CERTIFICATE_PATH" ] || { echo "Error: Certificate file not found: ${CERTIFICATE_PATH}" >&2; exit 1; }
            shift
        ;;
        -ckf     | --certkeyfile         )
            [ -n "$2" ] && CERTIFICATE_KEY_PATH="$2"
            [[ "$CERTIFICATE_KEY_PATH" != /* ]] && CERTIFICATE_KEY_PATH="$(cd "$(dirname "$CERTIFICATE_KEY_PATH")" && pwd)/$(basename "$CERTIFICATE_KEY_PATH")"
            [ -f "$CERTIFICATE_KEY_PATH" ] || { echo "Error: Certificate key file not found: ${CERTIFICATE_KEY_PATH}" >&2; exit 1; }
            shift
        ;;
        -h | -? | --help )
            echo 
            echo "PRELIMINARY PARAMETERS (Docker registry auth):"
            echo "  --registry          <URL>               Docker registry URL (e.g., https://myregistry.com:5000)"
            echo "  --username          <username>          Username for Docker registry login"
            echo "  --password          <password>          Password for Docker registry"

            echo 
            echo "INSTALL/UPGRADE MODE:"
            echo "  --installationtype  <edition>           Edition to install: community, developer, enterprise"
            echo "  --update            <true|false>        true to upgrade existing components"
            echo "  --uninstall         <true|false>        true to remove existing ${PRODUCT} (containers, volumes, configs)"
            echo "  --noninteractive    <true|false>        true to auto-confirm prompts (default: false)"

            echo 
            echo "GENERAL OPTIONS:"
            echo "  --skiphardwarecheck <true|false>        Skip hardware checks (RAM, disk, CPU; default: false)"
            echo "  --offline           <true|false>        Offline mode: use local images only (requires pre-pulled images)"
            echo "  --makeswap          <true|false>        Create swap file (default: true)"
            echo "  --extrahosts        <DOMAIN:IP>         Specify extra hostname resolution"
            echo "  --volumesdir        <path>              Host dir for Docker volumes (default: /var/lib/docker/volumes)"

            echo 
            echo "${PRODUCT_NAME^^} OPTIONS:"
            echo "  --installdocspace   <true|false>        Install/update ${PRODUCT_NAME} (true to install/update)"
            echo "  --stack-mode        <true|false>        Install services in containers with the appropriate runtime"
            echo "  --docspaceversion   <version>           ${PRODUCT_NAME} version tag (e.g., 3.2.0)"
            echo "  --docspacehost      <hostname>          Hostname or IP for ${PRODUCT_NAME} (default: localhost)"
            echo "  --externalport      <port>              External port for ${PRODUCT_NAME} (default: 80)"
            echo "  --machinekey        <key>               core.machinekey for encryption (default: random key)"

            echo 
            echo "DOCUMENT SERVER OPTIONS:"
            echo "  --installdocs       <true|false>        Install/update Document Server (true to install/update)"
            echo "  --docsimage         <image_name>        Docker image for Document Server (e.g., onlyoffice/documentserver)"
            echo "  --docsversion       <version>           Document Server version tag (e.g., 8.2.3.1)"
            echo "  --docsurl           <URL>               URL for Document Server (e.g., http://docs.example.com:8083)"
            echo "  --jwtheader         <header_name>       HTTP header for JWT tokens (e.g., AuthorizationJwt)"
            echo "  --jwtsecret         <secret>            JWT secret key (default: random key)"

            echo 
            echo "MICROSERVICES OPTIONS:"
            echo "  RabbitMQ:"
            echo "    --installrabbitmq       <true|false>         true to deploy RabbitMQ container"
            echo "    --rabbitmqprotocol      <protocol>           Protocol for RabbitMQ (default: amqp)"
            echo "    --rabbitmqhost          <host>               Host/IP of RabbitMQ (default: localhost)"
            echo "    --rabbitmqport          <port>               RabbitMQ port (default: 5672)"
            echo "    --rabbitmqusername      <username>           RabbitMQ username"
            echo "    --rabbitmqpassword      <password>           RabbitMQ password"
            echo "    --rabbitmqvirtualhost   <vhost>              RabbitMQ virtual host (default \"/\")"
            echo 
            echo "  Redis:"
            echo "    --installredis          <true|false>         true to deploy Redis container"
            echo "    --redishost             <host>               Host/IP of Redis (default: localhost)"
            echo "    --redisport             <port>               Redis port (default: 6379)"
            echo "    --redisusername         <username>           Redis username (if required)"
            echo "    --redispassword         <password>           Redis password (if required)"
            echo 
            echo "  MySQL:"
            echo "    --installmysql          <true|false>         true to deploy MySQL container"
            echo "    --mysqlrootpassword     <password>           Root password for MySQL"
            echo "    --mysqldatabase         <db_name>            Database name for ${PRODUCT_NAME} (e.g., ${PRODUCT})"
            echo "    --mysqluser             <username>           DB user for ${PRODUCT_NAME}"
            echo "    --mysqlpassword         <password>           Password for ${PRODUCT_NAME} DB user"
            echo "    --mysqlhost             <host>               Host/IP of MySQL (default: localhost)"
            echo "    --mysqlport             <port>               MySQL port (default: 3306)"
            echo 
            echo "  OpenSearch:"
            echo "    --installelastic        <true|false>         true to deploy OpenSearch container"
            echo "    --elasticprotocol       <http|https>         Protocol for OpenSearch (default: http)"
            echo "    --elastichost           <host>               Host/IP of OpenSearch (default: localhost)"
            echo "    --elasticport           <port>               OpenSearch port (default: 9200)"
            echo 
            echo "  Fluent-Bit:"
            echo "    --installfluentbit      <true|false>         true to deploy Fluent-Bit for log aggregation"
            echo 
            echo "  OpenSearch Dashboards:"
            echo "    --dashboardsusername    <username>           Username for OpenSearch Dashboards UI"
            echo "    --dashboardspassword    <password>           Password for Dashboards UI"
            echo
            echo "Let's Encrypt:"
            echo "  --letsencryptdomain <domain>          Domain for Let's Encrypt (example.com / *.example.com / s1.example.com, s2.example.com)"
            echo "  --letsencryptmail   <email>           Admin email for Let's Encrypt (e.g., admin@example.com)"
            echo 
            echo "SSL / HTTPS:"
            echo "  --certdomain     <domain>             Domain for existing SSL cert (example.com / *.example.com / s1.example.com, s2.example.com)"
            echo "  --certfile       <path>               Path to SSL cert (.pem, .pfx, .der, .cer, PKCS#7)"
            echo "  --certkeyfile    <path>               Path to SSL key (used with --certfile)"
            exit 0
        ;;
        * ) echo "Unknown parameter $1" 1>&2; exit 1 ;;
    esac
    shift
done

