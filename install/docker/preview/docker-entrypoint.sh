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
    log "🌐 Initializing nginx..." && /nginx/docker-entrypoint.sh
    log "✅ Initialization complete - starting supervisord"
    log "=================================="
    exec supervisord -n
}

main
