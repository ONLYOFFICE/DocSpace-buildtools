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
        -it      | --installationtype    ) [ -n "$2" ] && INSTALLATION_TYPE="${2^^}"                                              && shift ;;
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
        -led     | --letsencryptdomain   ) [ -n "$2" ] && LETS_ENCRYPT_DOMAIN=$2                                                  && shift ;;
        -lem     | --letsencryptmail     ) [ -n "$2" ] && LETS_ENCRYPT_MAIL=$2                                                    && shift ;;
        -du      | --dashboardsusername  ) [ -n "$2" ] && DASHBOARDS_USERNAME=$2                                                  && shift ;;
        -dp      | --dashboardspassword  ) [ -n "$2" ] && DASHBOARDS_PASSWORD=$2                                                  && shift ;;
        -noni    | --noninteractive      ) [ -n "$2" ] && NON_INTERACTIVE=$2                                                      && shift ;;
        -uni     | --uninstall           ) [ -n "$2" ] && UNINSTALL=$2 && [ "$UNINSTALL" = "true" ] && OFFLINE_IMAGE_LOAD="true"  && shift ;;
        -off     | --offline             ) [ -n "$2" ] && OFFLINE_INSTALLATION=$2                                                 && shift ;;
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
            echo "  Usage: bash $HELP_TARGET [PARAMETER] [[PARAMETER], ...]"
            echo
            echo "    Parameters:"
            echo "      -reg, --registry                  docker registry URL (e.g., https://myregistry.com:5000)"
            echo "      -un, --username                   docker registry login"
            echo "      -p, --password                    docker registry password"
            echo "      -it, --installation_type          installation type (community|developer|enterprise)"
            echo "      -skiphc, --skiphardwarecheck      skip hardware check (true|false)"
            echo "      -u, --update                      use to update existing components (true|false)"
            echo "      -ids, --installdocspace           install or update $PRODUCT (true|false)"
            echo "      -dsv, --docspaceversion           select the $PRODUCT version"
            echo "      -dsh, --docspacehost              $PRODUCT host"
            echo "      -env, --environment               $PRODUCT environment"
            echo "      -mk, --machinekey                 setting for core.machinekey"
            echo "      -ep, --externalport               external $PRODUCT port (default value 80)"
            echo "      -vd, --volumesdir                 directory for storing Docker volumes (default value /var/lib/docker/volumes)"
            echo "      -idocs, --installdocs             install or update document server (true|false)"
            echo "      -docsi, --docsimage               document server image name"
            echo "      -docsv, --docsversion             document server version"
            echo "      -docsurl, --docsurl               $PACKAGE_SYSNAME docs server address (example http://$PACKAGE_SYSNAME-docs-address:8083)"
            echo "      -jh, --jwtheader                  defines the HTTP header that will be used to send the JWT"
            echo "      -js, --jwtsecret                  defines the secret key to validate the JWT in the request"
            echo "      -irbt, --installrabbitmq          install or update rabbitmq (true|false)"
            echo "      -irds, --installredis             install or update redis (true|false)"
            echo "      -imysql, --installmysql           install or update mysql (true|false)"
            echo "      -ies, --installelastic            install or update elasticsearch (true|false)"
            echo "      -ifb, --installfluentbit          install or update fluent-bit (true|false)"
            echo "      -du, --dashboardsusername         username for authorization in /dashboards/"
            echo "      -dp, --dashboardspassword         password for authorization in /dashboards/"
            echo "      -espr, --elasticprotocol          the protocol for the connection to elasticsearch (default value http)"
            echo "      -esh, --elastichost               the IP address or hostname of the elasticsearch"
            echo "      -esp, --elasticport               elasticsearch port number (default value 9200)"
            echo "      -rdsh, --redishost                the IP address or hostname of the redis server"
            echo "      -rdsp, --redisport                redis server port number (default value 6379)"
            echo "      -rdsu, --redisusername            redis user name"
            echo "      -rdspass, --redispassword         password set for redis account"
            echo "      -rbpr, --rabbitmqprotocol         the protocol for the connection to rabbitmq server (default value amqp)"
            echo "      -rbth, --rabbitmqhost             the IP address or hostname of the rabbitmq server"
            echo "      -rbtp, --rabbitmqport             rabbitmq server port number (default value 5672)"
            echo "      -rbtu, --rabbitmqusername         username for rabbitmq server account"
            echo "      -rbtpass, --rabbitmqpassword      password set for rabbitmq server account"
            echo "      -rbtvh, --rabbitmqvirtualhost     rabbitmq virtual host (default value \"/\")"
            echo "      -mysqlrp, --mysqlrootpassword     mysql server root password"
            echo "      -mysqld, --mysqldatabase          $PRODUCT database name"
            echo "      -mysqlu, --mysqluser              $PRODUCT database user"
            echo "      -mysqlp, --mysqlpassword          $PRODUCT database password"
            echo "      -mysqlh, --mysqlhost              mysql server host"
            echo "      -mysqlport, --mysqlport           mysql server port number (default value 3306)"
            echo "      -led, --letsencryptdomain         defines the domain for Let's Encrypt certificate"
            echo "      -lem, --letsencryptmail           defines the domain administrator mail address for Let's Encrypt certificate"
            echo "      -cf, --certfile                   path to the certificate file for the domain"
            echo "      -ckf, --certkeyfile               path to the private key file for the certificate"
            echo "      -off, --offline                   set the script for offline installation (true|false)"
            echo "      -noni, --noninteractive           auto confirm all questions (true|false)"
            echo "      -dbm, --databasemigration         database migration (true|false)"
            echo "      -ms, --makeswap                   make swap file (true|false)"
            echo "      -uni, --uninstall                 uninstall existing installation (true|false)"
            echo "      -?, -h, --help                    this help"
            echo
            echo "    Install all the components without document server:"
            echo "      bash $HELP_TARGET -idocs false"
            echo
            echo "    Install Document Server only. Skip the installation of mysql, $PRODUCT, rabbitmq, redis:"
            echo "      bash $HELP_TARGET -ids false -idocs true -imysql false -irbt false -irds false"
            echo
            echo "    Update all installed components. Stop the containers that need to be updated, remove them and run the latest versions of the corresponding components."
            echo "    The portal data should be picked up automatically:"
            echo "      bash $HELP_TARGET -u true"
            echo
            echo "    Update Document Server only to version 7.2.1.34 and skip the update for all other components:"
            echo "      bash $HELP_TARGET -u true -docsi ${PACKAGE_SYSNAME}/documentserver-ee -docsv 7.2.1.34 -idocs true -ids false -irbt false -irds false"
            echo
            echo "    Update $PRODUCT only to version 1.2.0 and skip the update for all other components:"
            echo "      bash $HELP_TARGET -u true -dsv v1.2.0 -idocs false -irbt false -irds false"
            echo
            exit 0
        ;;
        * ) echo "Unknown parameter $1" 1>&2; exit 1 ;;
    esac
    shift
done

