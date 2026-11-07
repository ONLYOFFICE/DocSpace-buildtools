#!/bin/bash

export SPRING_APPLICATION_NAME="${1}"

export JDBC_URL="${MYSQL_HOST:-$MYSQL_CONTAINER_NAME}${MYSQL_HOST:+:$MYSQL_PORT}"
export JDBC_DATABASE=${MYSQL_DATABASE:-"onlyoffice"}
export JDBC_USER_NAME=${MYSQL_USER:-"onlyoffice_user"}
export JDBC_PASSWORD=${MYSQL_PASSWORD:?MYSQL_PASSWORD must be set}

export REDIS_HOST=${REDIS_HOST:-${REDIS_CONTAINER_NAME}}
export REDIS_PORT=${REDIS_PORT:-"6379"}
export REDIS_USERNAME=${REDIS_USER_NAME}
export REDIS_PASSWORD=${REDIS_PASSWORD}

export RABBIT_PROTOCOL=${RABBIT_PROTOCOL:-"amqp"}
export RABBIT_HOST=${RABBIT_HOST:-${RABBIT_CONTAINER_NAME}}
export RABBIT_USER_NAME=${RABBIT_USER_NAME:-"guest"}
export RABBIT_PASSWORD=${RABBIT_PASSWORD:-"guest"}
export RABBIT_VIRTUAL_HOST=${RABBIT_VIRTUAL_HOST:-"/"}
export RABBIT_URI="${RABBIT_URI:-${RABBIT_PROTOCOL}://${RABBIT_USER_NAME}:${RABBIT_PASSWORD}@${RABBIT_HOST}${RABBIT_VIRTUAL_HOST}}"

export LOG_FILE_PATH="${LOG_DIR:-"/var/log/onlyoffice"}/${SPRING_APPLICATION_NAME}.log"

if [ "$1" = "supervisord" ]; then
    exec "$@"
fi

# Refuse to start without secrets; the sample values that shipped in .env only get a warning, as changing them makes encrypted data unreadable
for secret_name in SPRING_APPLICATION_SIGNATURE_SECRET SPRING_APPLICATION_ENCRYPTION_SECRET; do
    secret_value="${!secret_name}"
    if [ -z "$secret_value" ]; then
        echo "$secret_name must be set to a unique value" >&2
        exit 1
    elif [ "$secret_value" = "your_core_machinekey" ] || [ "$secret_value" = "your_secret_key" ]; then
        echo "WARNING: $secret_name still has its public sample value; set a unique value for new installations" >&2
    fi
done

exec java -jar ${BUILD_PATH}/services/${SPRING_APPLICATION_NAME}/app.jar
