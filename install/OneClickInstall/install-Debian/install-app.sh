#!/bin/bash

set -e

cat<<EOF

#######################################
#  INSTALL APP
#######################################

EOF
apt-get -y update

ds_pkg_name="${package_sysname}-documentserver"
case "${INSTALLATION_TYPE}" in
	"DEVELOPER") ds_pkg_name+="-de" ;;
	"ENTERPRISE") ds_pkg_name+="-ee" ;;
esac

if [ "$UPDATE" = "true" ] && [ "$DOCUMENT_SERVER_INSTALLED" = "true" ]; then
	ds_pkg_installed_name=$(dpkg -l | grep "${package_sysname}"-documentserver | tail -n1 | awk '{print $2}')
	if [ -n "${ds_pkg_installed_name}" ] && [ "${ds_pkg_installed_name}" != "${ds_pkg_name}" ]; then
		debconf-get-selections | grep ^"${ds_pkg_installed_name}" | sed s/"${ds_pkg_installed_name}"/"${ds_pkg_name}"/g | debconf-set-selections
		DEBIAN_FRONTEND=noninteractive apt-get purge -yq "${ds_pkg_installed_name}"
		apt-get install -yq "${ds_pkg_name}"
		RECONFIGURE_PRODUCT="true"
	else
		apt-get install -y --only-upgrade "${ds_pkg_name}"
	fi
fi

if [ "$DOCUMENT_SERVER_INSTALLED" = "false" ]; then
	DS_PORT=${DS_PORT:-8083}

	DS_DB_HOST=localhost
	DS_DB_NAME=$DS_COMMON_NAME
	DS_DB_USER=$DS_COMMON_NAME
	DS_DB_PWD=$DS_COMMON_NAME
	
	DS_JWT_ENABLED=${DS_JWT_ENABLED:-true}
	DS_JWT_SECRET=${DS_JWT_SECRET:-$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)}
	DS_JWT_HEADER=${DS_JWT_HEADER:-AuthorizationJwt}

	if ! su - postgres -s /bin/bash -c "psql -lqt" | cut -d \| -f 1 | grep -q "${DS_DB_NAME}"; then
		su - postgres -s /bin/bash -c "psql -c \"CREATE USER ${DS_DB_USER} WITH password '${DS_DB_PWD}';\""
		su - postgres -s /bin/bash -c "psql -c \"CREATE DATABASE ${DS_DB_NAME} OWNER ${DS_DB_USER};\""
	fi

	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/ds-port select "$DS_PORT" | sudo debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/db-pwd select "$DS_DB_PWD" | sudo debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/db-user select "$DS_DB_USER" | sudo debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/db-name select "$DS_DB_NAME" | sudo debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/jwt-enabled select "${DS_JWT_ENABLED}" | sudo debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/jwt-secret select "${DS_JWT_SECRET}" | sudo debconf-set-selections
	echo "${package_sysname}"-documentserver "$DS_COMMON_NAME"/jwt-header select "${DS_JWT_HEADER}" | sudo debconf-set-selections
	
	apt-get install -yq "${ds_pkg_name}"
fi

if [ "$MAKESWAP" == "true" ]; then
	make_swap
fi

if [ "$PRODUCT_INSTALLED" = "false" ]; then
	echo "${product}" "${product}"/db-pwd select "$MYSQL_SERVER_PASS" | sudo debconf-set-selections
	echo "${product}" "${product}"/db-user select "$MYSQL_SERVER_USER" | sudo debconf-set-selections
	echo "${product}" "${product}"/db-name select "$MYSQL_SERVER_DB_NAME" | sudo debconf-set-selections
	
	apt-get install -y "${product}" || true #Fix error 'Failed to fetch'
	apt-get install -y "${product}"
elif [ "$UPDATE" = "true" ] && [ "$PRODUCT_INSTALLED" = "true" ]; then
	CURRENT_VERSION=$(dpkg-query -W -f='${Version}' "${product}" 2>/dev/null)
	AVAILABLE_VERSIONS=$(apt show "${product}" 2>/dev/null | grep -E '^Version:' | awk '{print $2}')
	if [[ "$AVAILABLE_VERSIONS" != *"$CURRENT_VERSION"* ]]; then
		apt-get install -o DPkg::options::="--force-confnew" -y --only-upgrade "${product}" opensearch="${ELASTIC_VERSION}"
	elif [ "${RECONFIGURE_PRODUCT}" = "true" ]; then
		DEBIAN_FRONTEND=noninteractive dpkg-reconfigure "${product}"
	fi
fi

#######################################
#  POST-DEBUG SNAPSHOT (read-only)
#######################################
{
  echo ""
  echo "========== DEBUG: Environment =========="
  date
  uname -a
  command -v lsb_release >/dev/null 2>&1 && lsb_release -a || true
  echo "UPDATE=${UPDATE:-unset} DOCUMENT_SERVER_INSTALLED=${DOCUMENT_SERVER_INSTALLED:-unset} PRODUCT_INSTALLED=${PRODUCT_INSTALLED:-unset}"
  echo "INSTALLATION_TYPE=${INSTALLATION_TYPE:-unset} package_sysname=${package_sysname:-unset} product=${product:-unset}"

  echo ""
  echo "========== DEBUG: Package versions =========="
  for p in opensearch rabbitmq-server "${ds_pkg_name}" "${product}"; do
    printf "%-28s : " "$p"
    dpkg-query -W -f='${Version}\n' "$p" 2>/dev/null || echo "not installed"
  done

  echo ""
  echo "========== DEBUG: Sysctl & OS settings =========="
  printf "vm.max_map_count: "
  sysctl -n vm.max_map_count 2>/dev/null || echo "n/a"
  printf "OpenSearch config exists: "
  [ -f /etc/opensearch/opensearch.yml ] && echo "yes" || echo "no"
  [ -f /etc/opensearch/opensearch.yml ] && { echo "--- /etc/opensearch/opensearch.yml (head) ---"; sed -n '1,40p' /etc/opensearch/opensearch.yml; echo "-------------------------------------------"; }

  echo ""
  echo "========== DEBUG: Systemd quick states =========="
  units=( rabbitmq-server opensearch ds-docservice.service ds-converter.service docspace-files.service docspace-files-services.service docspace-identity-api.service docspace-identity-authorization.service )
  for u in "${units[@]}"; do
    if systemctl list-unit-files | grep -q "^${u}"; then
      printf "%-34s : " "$u"
      systemctl show -p ActiveState -p SubState -p UnitFileState "$u" | tr '\n' ' '; echo
    fi
  done

  echo ""
  echo "========== DEBUG: Listening ports =========="
  ss -ltnp | egrep ':(5672|9200|8000|5011|5013|5099|9834|9899)\s' || true

  echo ""
  echo "========== DEBUG: Health probes =========="
  echo "- AMQP (RabbitMQ) 127.0.0.1:5672 ->"
  timeout 2 bash -c 'echo > /dev/tcp/127.0.0.1/5672' && echo "tcp connect OK" || echo "connect FAILED"
  echo "- OpenSearch http://127.0.0.1:9200 ->"
  curl -sS -m 2 http://127.0.0.1:9200/ || echo "curl failed"
  echo
  echo "- Identity API http://127.0.0.1:9899/health ->"
  curl -sS -m 2 http://127.0.0.1:9899/health || echo "curl failed"
  echo
  echo "- Identity Authorization http://127.0.0.1:9834/health ->"
  curl -sS -m 2 http://127.0.0.1:9834/health || echo "curl failed"
  echo

  echo ""
  echo "========== DEBUG: Recent logs (tail) =========="
  journalctl -u rabbitmq-server -u opensearch -u ds-docservice.service -u ds-converter.service -u docspace-files.service -u docspace-files-services.service --no-pager -n 60 || true

  echo ""
  echo "========== DEBUG: DocumentServer logs (tail) =========="
  for f in /var/log/onlyoffice/documentserver/docservice/out.log /var/log/onlyoffice/documentserver/converter/out.log; do
    [ -f "$f" ] && { echo "--- $f (tail -n 50) ---"; tail -n 50 "$f"; }
  done

  echo ""
  echo "========== DEBUG: DocSpace service logs (tail) =========="
  for f in /var/log/onlyoffice/docspace/files-services.log /var/log/onlyoffice/docspace/files.log; do
    [ -f "$f" ] && { echo "--- $f (tail -n 50) ---"; tail -n 50 "$f"; }
  done
} || true
#######################################

echo ""
echo "$RES_INSTALL_SUCCESS"
echo "$RES_QUESTIONS"
echo ""
