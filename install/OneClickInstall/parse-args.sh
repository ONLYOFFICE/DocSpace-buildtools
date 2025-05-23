#!/usr/bin/env bash

PACKAGE_SYSNAME="onlyoffice"
INSTALLATION_TYPE="ENTERPRISE"
EXTERNAL_PORT="80"
SKIP_HARDWARE_CHECK="false"

while [ "$1" != "" ]; do
	case $1 in

		-u | --update )
			if [ "$2" != "" ]; then
				UPDATE=$2
				shift
			fi
		;;

		-reg | --registry )
			if [ "$2" != "" ]; then
				REGISTRY_URL=$2
				shift
			fi
		;;

		-un | --username )
			if [ "$2" != "" ]; then
				USERNAME=$2
				shift
			fi
		;;

		-p | --password )
			if [ "$2" != "" ]; then
				PASSWORD=$2
				shift
			fi
		;;

		-ids | --installdocspace )
			if [ "$2" != "" ]; then
				INSTALL_PRODUCT=$2
				shift
			fi
		;;

		-idocs | --installdocs )
			if [ "$2" != "" ]; then
				INSTALL_DOCUMENT_SERVER=$2
				shift
			fi
		;;

		-imysql | --installmysql )
			if [ "$2" != "" ]; then
				INSTALL_MYSQL_SERVER=$2
				shift
			fi
		;;		
		
		-irbt | --installrabbitmq )
			if [ "$2" != "" ]; then
				INSTALL_RABBITMQ=$2
				shift
			fi
		;;

		-irds | --installredis )
			if [ "$2" != "" ]; then
				INSTALL_REDIS=$2
				shift
			fi
		;;

		-ht | --helptarget )
			if [ "$2" != "" ]; then
				HELP_TARGET=$2
				shift
			fi
		;;

		-mysqld | --mysqldatabase )
			if [ "$2" != "" ]; then
				MYSQL_DATABASE=$2
				shift
			fi
		;;

		-mysqlrp | --mysqlrootpassword )
			if [ "$2" != "" ]; then
				MYSQL_ROOT_PASSWORD=$2
				shift
			fi
		;;

		-mysqlu | --mysqluser )
			if [ "$2" != "" ]; then
				MYSQL_USER=$2
				shift
			fi
		;;

		-mysqlh | --mysqlhost )
			if [ "$2" != "" ]; then
				MYSQL_HOST=$2
				shift
			fi
		;;

		-mysqlport | --mysqlport )
			if [ "$2" != "" ]; then
				MYSQL_PORT=$2
				shift
			fi
		;;

		-mysqlp | --mysqlpassword )
			if [ "$2" != "" ]; then
				MYSQL_PASSWORD=$2
				shift
			fi
		;;

		-espr | --elasticprotocol )
			if [ "$2" != "" ]; then
				ELK_SHEME=$2
				shift
			fi
		;;

		-esh | --elastichost )
			if [ "$2" != "" ]; then
				ELK_HOST=$2
				shift
			fi
		;;

		-esp | --elasticport )
			if [ "$2" != "" ]; then
				ELK_PORT=$2
				shift
			fi
		;;

		-skiphc | --skiphardwarecheck )
			if [ "$2" != "" ]; then
				SKIP_HARDWARE_CHECK=$2
				shift
			fi
		;;

		-ep | --externalport )
			if [ "$2" != "" ]; then
				EXTERNAL_PORT=$2
				shift
			fi
		;;

		-dsh | --docspacehost )
			if [ "$2" != "" ]; then
				APP_URL_PORTAL=$2
				shift
			fi
		;;
		
		-mk | --machinekey )
			if [ "$2" != "" ]; then
				APP_CORE_MACHINEKEY=$2
				shift
			fi
		;;
		
		-env | --environment )
			if [ "$2" != "" ]; then
				ENV_EXTENSION=$2
				shift
			fi
		;;

		-s | --status )
			if [ "$2" != "" ]; then
				STATUS=$2
				IMAGE_NAME="${PACKAGE_SYSNAME}/${STATUS}${PRODUCT}-api"
				shift
			fi
		;;

		-ls | --localscripts )
			if [ "$2" != "" ]; then
				shift
			fi
		;;
		
		-dsv | --docspaceversion )
			if [ "$2" != "" ]; then
				DOCKER_TAG=$2
				shift
			fi
		;;
		
		-gb | --gitbranch )
			if [ "$2" != "" ]; then
				PARAMETERS="$PARAMETERS ${1}"
				GIT_BRANCH=$2
				shift
			fi
		;;
		
		-docsi | --docsimage )
			if [ "$2" != "" ]; then
				DOCUMENT_SERVER_IMAGE_NAME=$2
				shift
			fi
		;;
		
		-docsv | --docsversion )
			if [ "$2" != "" ]; then
				DOCUMENT_SERVER_VERSION=$2
				shift
			fi
		;;
		
		-docsurl | --docsurl )
			if [ "$2" != "" ]; then
				DOCUMENT_SERVER_URL_EXTERNAL=$2
				shift
			fi
		;;
		
		-dbm | --databasemigration )
			if [ "$2" != "" ]; then
				DATABASE_MIGRATION=$2
				shift
			fi
		;;

		-jh | --jwtheader )
			if [ "$2" != "" ]; then
				DOCUMENT_SERVER_JWT_HEADER=$2
				shift
			fi
		;;

		-js | --jwtsecret )
			if [ "$2" != "" ]; then
				DOCUMENT_SERVER_JWT_SECRET=$2
				shift
			fi
		;;

		-it | --installation_type )
			if [ "$2" != "" ]; then
				INSTALLATION_TYPE="${2^^}"
				shift
			fi
		;;

		-ms | --makeswap )
			if [ "$2" != "" ]; then
				MAKESWAP=$2
				shift
			fi
		;;

		-ies | --installelastic )
			if [ "$2" != "" ]; then
				INSTALL_ELASTICSEARCH=$2
				shift
			fi
		;;

		-ifb | --installfluentbit )
			if [ "$2" != "" ]; then
				INSTALL_FLUENT_BIT=$2
				shift
			fi
		;;

		-rdsh | --redishost )
			if [ "$2" != "" ]; then
				REDIS_HOST=$2
				shift
			fi
		;;

		-rdsp | --redisport )
			if [ "$2" != "" ]; then
				REDIS_PORT=$2
				shift
			fi
		;;

		-rdsu | --redisusername )
			if [ "$2" != "" ]; then
				REDIS_USER_NAME=$2
				shift
			fi
		;;

		-rdspass | --redispassword )
			if [ "$2" != "" ]; then
				REDIS_PASSWORD=$2
				shift
			fi
		;;

		-rbpr | --rabbitmqprotocol )
			if [ "$2" != "" ]; then
				RABBIT_PROTOCOL=$2
				shift
			fi
		;;

		-rbth | --rabbitmqhost )
			if [ "$2" != "" ]; then
				RABBIT_HOST=$2
				shift
			fi
		;;

		-rbtp | --rabbitmqport )
			if [ "$2" != "" ]; then
				RABBIT_PORT=$2
				shift
			fi
		;;

		-rbtu | --rabbitmqusername )
			if [ "$2" != "" ]; then
				RABBIT_USER_NAME=$2
				shift
			fi
		;;

		-rbtpass | --rabbitmqpassword )
			if [ "$2" != "" ]; then
				RABBIT_PASSWORD=$2
				shift
			fi
		;;

		-rbtvh | --rabbitmqvirtualhost )
			if [ "$2" != "" ]; then
				RABBIT_VIRTUAL_HOST=$2
				shift
			fi
		;;

		-led | --letsencryptdomain )
			if [ "$2" != "" ]; then
				LETS_ENCRYPT_DOMAIN=$2
				shift
			fi
		;;

		-lem | --letsencryptmail )
			if [ "$2" != "" ]; then
				LETS_ENCRYPT_MAIL=$2
				shift
			fi
		;;

		-cf | --certfile )
			if [ "$2" != "" ]; then
				CERTIFICATE_PATH=$2
				shift
			fi
		;;

		-ckf | --certkeyfile )
			if [ "$2" != "" ]; then
				CERTIFICATE_KEY_PATH=$2
				shift
			fi
		;;

		-du | --dashboardsusername )
			if [ "$2" != "" ]; then
				DASHBOARDS_USERNAME=$2
				shift
			fi
		;;

		-dp | --dashboardspassword )
			if [ "$2" != "" ]; then
				DASHBOARDS_PASSWORD=$2
				shift
			fi
		;;
		
		-noni | --noninteractive )
			if [ "$2" != "" ]; then
				NON_INTERACTIVE=$2
				shift
			fi
		;;

		-uni | --uninstall)
			if [ "$2" != "" ]; then
				UNINSTALL=$2
            	shift
			fi

        ;;

		-off | --offline )
			if [ "$2" != "" ]; then
				OFFLINE_INSTALLATION=$2
				shift
			fi
		;;

		-vd | --volumesdir )
			if [ "$2" != "" ]; then
				VOLUMES_DIR=$2
				[[ "$VOLUMES_DIR" == "$BASE_DIR"* ]] && { echo "Warning: Please change the volumes directory, as $BASE_DIR will be removed during an update."; exit 1; }
				shift
			fi
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
			echo "      -jh, --jwtheader                  defines the http header that will be used to send the JWT"
			echo "      -js, --jwtsecret                  defines the secret key to validate the JWT in the request"	
			echo "      -irbt, --installrabbitmq          install or update rabbitmq (true|false)"	
			echo "      -irds, --installredis             install or update redis (true|false)"
			echo "      -imysql, --installmysql           install or update mysql (true|false)"		
			echo "      -ies, --installelastic            install or update elasticsearch (true|false)"
			echo "      -ifb, --installfluentbit          install or update fluent-bit (true|false)"
			echo "      -du, --dashboardsusername         login for authorization in /dashboards/"
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

		* )
			echo "Unknown parameter $1" 1>&2
			exit 1
		;;
	esac
	shift
done
