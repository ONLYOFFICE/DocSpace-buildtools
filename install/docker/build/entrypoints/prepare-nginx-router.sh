#!/bin/bash
WRONG_PORTAL_NAME_URL=${WRONG_PORTAL_NAME_URL:-""}
REDIS_HOST=${REDIS_HOST:-"${REDIS_CONTAINER_NAME}"}
REDIS_PORT=${REDIS_PORT:-"6379"}
REDIS_USER=${REDIS_USER:-""}
REDIS_PASSWORD=${REDIS_PASSWORD:-""}
REDIS_DB=${REDIS_DB:-"0"}

envsubst '$MAP_HASH_BUCKET_SIZE,$COUNT_WORKER_CONNECTIONS' < /etc/nginx/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf
sed -i "s~\(redis_host =\).*~\1 \"$REDIS_HOST\"~" /etc/nginx/conf.d/onlyoffice.conf
sed -i "s~\(redis_port =\).*~\1 $REDIS_PORT~" /etc/nginx/conf.d/onlyoffice.conf
sed -i "s~\(redis_user =\).*~\1 \"$REDIS_USER\"~" /etc/nginx/conf.d/onlyoffice.conf
sed -i "s~\(redis_pass =\).*~\1 \"$REDIS_PASSWORD\"~" /etc/nginx/conf.d/onlyoffice.conf
sed -i "s~\(redis_db =\).*~\1 $REDIS_DB~" /etc/nginx/conf.d/onlyoffice.conf
sed -i "s~\(\"wrongPortalNameUrl\":\).*,~\1 \"${WRONG_PORTAL_NAME_URL}\",~g" /var/www/public/scripts/config.json
# Without DASHBOARDS_PASSWORD the login is locked with a random password nobody knows, instead of a guessable default
if [ -z "${DASHBOARDS_PASSWORD:-}" ]; then
    echo "DASHBOARDS_PASSWORD is empty: /dashboards stays locked until it is set" >&2
    DASHBOARDS_PASSWORD=$(openssl rand -hex 32)
fi
echo "${DASHBOARDS_USERNAME:-onlyoffice}:$(openssl passwd -6 -stdin <<< "$DASHBOARDS_PASSWORD")" > /etc/nginx/.htpasswd_dashboards
