#!/bin/bash
set -euo pipefail

# Default values
PATH_TO_CONF=${PATH_TO_CONF:-"/app/onlyoffice/config"}
SRC_PATH=${SRC_PATH:-"/app/onlyoffice/src"}
BACKEND_PATH="${SRC_PATH}/publish/services/backend"
DEBUG_INFO=${DEBUG_INFO:-"false"}
APP_CORE_BASE_DOMAIN=${APP_CORE_BASE_DOMAIN:-"localhost"}
APP_URL_PORTAL=${APP_URL_PORTAL:-"http://127.0.0.1:8092"}
: "${APP_CORE_MACHINEKEY:?APP_CORE_MACHINEKEY must be set}"

DOCUMENT_CONTAINER_NAME=${DOCUMENT_CONTAINER_NAME:-"onlyoffice-document-server"}
DOCUMENT_SERVER_URL_PUBLIC=${DOCUMENT_SERVER_URL_PUBLIC:-"/ds-vpath/"}
DOCUMENT_SERVER_URL_EXTERNAL=${DOCUMENT_SERVER_URL_EXTERNAL:-"http://${DOCUMENT_CONTAINER_NAME}"}
: "${DOCUMENT_SERVER_JWT_SECRET:?DOCUMENT_SERVER_JWT_SECRET must be set}"
DOCUMENT_SERVER_JWT_HEADER=${DOCUMENT_SERVER_JWT_HEADER:-"AuthorizationJwt"}
OAUTH_REDIRECT_URL=${OAUTH_REDIRECT_URL:-"https://service.onlyoffice.com/oauth2.aspx"}

HIDE_SETTINGS=[\n\"Monitoring\",\n\"LdapSettings\",\n\"DocService\",\n\"MailService\",\n\"PublicPortal\",\n\"ProxyHttpContent\",\n\"SpamSubscription\",\n\"FullTextSearch\",\n\"IdentityServer\"\n]

MYSQL_CONTAINER_NAME=${MYSQL_CONTAINER_NAME:-"localhost"}
MYSQL_HOST=${MYSQL_HOST:-${MYSQL_CONTAINER_NAME}}
MYSQL_PORT=${MYSQL_PORT:-"3306"}
MYSQL_DATABASE=${MYSQL_DATABASE:-"docspace"}
MYSQL_USER=${MYSQL_USER:-"onlyoffice_user"}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-"onlyoffice_pass"}
COMMAND_TIMEOUT=${COMMAND_TIMEOUT:-"100"}

MIGRATION_TYPE=${MIGRATION_TYPE:-"STANDALONE"}  # STANDALONE or SAAS

export MYSQL_PWD="$MYSQL_PASSWORD"
MYSQL_ARGS=(-h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER")
export CONNECTION_STRING="Server=${MYSQL_HOST};Port=${MYSQL_PORT};Database=${MYSQL_DATABASE};User ID=${MYSQL_USER};Password=${MYSQL_PASSWORD}"

SSL_MODE=${SSL_MODE:-"none"}
SSL_DOMAIN=${SSL_DOMAIN:-""}
SSL_CERT_PATH=${SSL_CERT_PATH:-""}
SSL_KEY_PATH=${SSL_KEY_PATH:-""}
SSL_EMAIL=${SSL_EMAIL:-""}
LETSENCRYPT_STAGING=${LETSENCRYPT_STAGING:-"false"}
LETSENCRYPT_FORCE_RENEW=${LETSENCRYPT_FORCE_RENEW:-"false"}
LETSENCRYPT_FAIL_OPEN=${LETSENCRYPT_FAIL_OPEN:-"false"}

setup_nginx_ssl() {
    mkdir -p /var/www/certbot /etc/letsencrypt

    write_http_nginx_conf() {
        cp /app/onlyoffice/template/nginx/onlyoffice-proxy.http.conf \
            /etc/nginx/conf.d/onlyoffice-proxy.conf
    }

    write_ssl_nginx_conf() {
        SERVER_NAME="$1" \
        SSL_CERTIFICATE="$2" \
        SSL_CERTIFICATE_KEY="$3" \
        envsubst '${SERVER_NAME} ${SSL_CERTIFICATE} ${SSL_CERTIFICATE_KEY}' \
            < /app/onlyoffice/template/nginx/onlyoffice-proxy.ssl.conf.template \
            > /etc/nginx/conf.d/onlyoffice-proxy.conf
    }

    if [[ "$SSL_MODE" == "custom" ]]; then
        if [[ -z "$SSL_DOMAIN" || -z "$SSL_CERT_PATH" || -z "$SSL_KEY_PATH" ]]; then
            log "SSL_MODE=custom requires SSL_DOMAIN, SSL_CERT_PATH, SSL_KEY_PATH"
            exit 1
        fi

        if [[ ! -f "$SSL_CERT_PATH" || ! -f "$SSL_KEY_PATH" ]]; then
            log "Custom SSL cert/key not found"
            exit 1
        fi

        write_ssl_nginx_conf "$SSL_DOMAIN" "$SSL_CERT_PATH" "$SSL_KEY_PATH"
        log "Using custom SSL certificate"
        return 0
    fi

    if [[ "$SSL_MODE" == "letsencrypt" ]]; then
        if [[ -z "$SSL_DOMAIN" ]]; then
            log "SSL_MODE=letsencrypt requires SSL_DOMAIN"
            exit 1
        fi

        if [[ -z "$SSL_EMAIL" ]]; then
            log "SSL_MODE=letsencrypt requires SSL_EMAIL"
            exit 1
        fi

        if ! command -v certbot >/dev/null 2>&1; then
            log "certbot is not installed in this image"
            log "Install certbot in Dockerfile or use a separate certbot service"
            exit 1
        fi

        local cert_file="/etc/letsencrypt/live/$SSL_DOMAIN/fullchain.pem"
        local key_file="/etc/letsencrypt/live/$SSL_DOMAIN/privkey.pem"

        if [[ ! -f "$cert_file" || ! -f "$key_file" || "$LETSENCRYPT_FORCE_RENEW" == "true" ]]; then
            log "Requesting Let's Encrypt certificate for $SSL_DOMAIN"
            log "Port 80 must be reachable from the Internet and point to this container"

            local staging_arg=()
            local renew_arg=()
            [[ "$LETSENCRYPT_STAGING" == "true" ]] && staging_arg=(--staging)
            [[ "$LETSENCRYPT_FORCE_RENEW" == "true" ]] && renew_arg=(--force-renewal)

            if certbot certonly \
                --standalone \
                --preferred-challenges http \
                --http-01-port 80 \
                --non-interactive \
                --agree-tos \
                --email "$SSL_EMAIL" \
                -d "$SSL_DOMAIN" \
                "${staging_arg[@]}" \
                "${renew_arg[@]}"; then
                log "Let's Encrypt certificate created"
            else
                log "Let's Encrypt certificate request failed"
                if [[ "$LETSENCRYPT_FAIL_OPEN" == "true" ]]; then
                    log "LETSENCRYPT_FAIL_OPEN=true, starting with HTTP only"
                    write_http_nginx_conf
                    return 0
                fi
                exit 1
            fi
        else
            log "Existing Let's Encrypt certificate found for $SSL_DOMAIN"
        fi

        write_ssl_nginx_conf "$SSL_DOMAIN" "$cert_file" "$key_file"
        log "Using Let's Encrypt certificate"
        return 0
    fi

    log "SSL disabled - HTTP only"
    write_http_nginx_conf
}
log() { echo "[$(date +'%F %T')] $1"; }

migration_count() {
    mysql "${MYSQL_ARGS[@]}" -sN -e "SELECT COUNT(*) FROM __EFMigrationsHistory;" \
        "$MYSQL_DATABASE" 2>/dev/null || echo "?"
}

# Function to update configuration files
update_configs() {
    log "📝 Updating configuration files..."

    JSON="node /usr/local/bin/json -I -f"

    # Main appsettings (connection, core, document server, misc)
    ${JSON} "${PATH_TO_CONF}/appsettings.json" \
        -e "this.ConnectionStrings.default.connectionString=process.env.CONNECTION_STRING+';Pooling=true;Character Set=utf8;AutoEnlist=false;SSL Mode=none;ConnectionReset=false;AllowPublicKeyRetrieval=true'" \
        -e "this.core['base-domain']=process.env.APP_CORE_BASE_DOMAIN" \
        -e "this.core.machinekey=process.env.APP_CORE_MACHINEKEY" \
        -e "this.files.docservice.url.public=process.env.DOCUMENT_SERVER_URL_PUBLIC" \
        -e "this['debug-info'].enabled=(process.env.DEBUG_INFO==='true')" \
        -e "this.files.docservice.url.internal=process.env.DOCUMENT_SERVER_URL_EXTERNAL+'/'" \
        -e "this.files.docservice.secret.value=process.env.DOCUMENT_SERVER_JWT_SECRET" \
        -e "this.files.docservice.secret.header=process.env.DOCUMENT_SERVER_JWT_HEADER" \
        -e "this.files.docservice.url.portal=process.env.APP_URL_PORTAL" \
        -e "this.core.notify.postman='services'"

    # API system (connection + core)
    ${JSON} "${PATH_TO_CONF}/apisystem.json" \
        -e "this.ConnectionStrings.default.connectionString=process.env.CONNECTION_STRING+';Pooling=true;Character Set=utf8;AutoEnlist=false;SSL Mode=none;ConnectionReset=false;AllowPublicKeyRetrieval=true'" \
        -e "this.core['base-domain']=process.env.APP_CORE_BASE_DOMAIN" \
        -e "this.core.machinekey=process.env.APP_CORE_MACHINEKEY"

    # OAuth redirect
    sed -i -E "s!\"https://service\.teamlab\.info/oauth2\.aspx\"!\"${OAUTH_REDIRECT_URL}\"!g" "${PATH_TO_CONF}/autofac.consumers.json"
    # Migration runner connection string
    sed -i -E "s!(\"ConnectionString\").*!\1: \"${CONNECTION_STRING//!/\\!};Command Timeout=${COMMAND_TIMEOUT}\"!g" "${BACKEND_PATH}/appsettings.runner.json"

    log "✅ Configuration files updated"
}

# Function to wait for MySQL and run migrations
run_migrations() {
    migration_args=()
    [[ ${MIGRATION_TYPE} == "STANDALONE" ]] && migration_args=(standalone=true)
    log "🔍 Starting migration process..."
    log "   Mode: ${MIGRATION_TYPE}"

    log "⏳ Waiting for MySQL to be ready..."
    MAX_RETRIES=30
    for ((counter = 1; counter <= MAX_RETRIES; counter++)); do
        mysql "${MYSQL_ARGS[@]}" -e "SELECT 1" "$MYSQL_DATABASE" >/dev/null 2>&1 && break
        [ "$counter" -eq "$MAX_RETRIES" ] && { log "❌ MySQL not available after ${MAX_RETRIES} attempts"; return 1; }
        sleep 2
    done
    log "✅ MySQL is ready!"
    log "📋 Current migration state: $(migration_count)"
    log "📋 Last 5 migrations:"
    mysql "${MYSQL_ARGS[@]}" -e "SELECT MigrationId, ProductVersion FROM __EFMigrationsHistory ORDER BY MigrationId DESC LIMIT 5;" \
        "$MYSQL_DATABASE" 2>/dev/null || log "   No migrations applied yet"

    log "🚀 Running database migration..."
    cd "${BACKEND_PATH}"
    if dotnet ASC.Migration.Runner.dll "${migration_args[@]}"; then
        log "✅ Migration completed successfully"
        log "📋 Updated migration state: $(migration_count)"
        log "📋 Most recent migrations:"
        mysql "${MYSQL_ARGS[@]}" -e "SELECT MigrationId, ProductVersion FROM __EFMigrationsHistory ORDER BY MigrationId DESC LIMIT 5;" \
            "$MYSQL_DATABASE" 2>/dev/null
        return 0
    fi
    log "❌ Migration failed"
    return 1
}

main() {
    echo "🚀 Starting Docker entrypoint..."
    echo "=================================="
    log "=== Starting initialization ==="
    update_configs
    run_migrations || { log "❌ Migration failed - exiting"; exit 1; }
    setup_nginx_ssl
    log "🌐 Initializing nginx..." && /nginx/docker-entrypoint.sh
    log "✅ Initialization complete - starting supervisord"
    log "=================================="
    exec supervisord -n
}

main

