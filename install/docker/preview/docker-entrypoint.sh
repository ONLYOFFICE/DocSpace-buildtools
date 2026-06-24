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

ELK_CONTAINER_NAME=${ELK_CONTAINER_NAME:-"onlyoffice-opensearch"}
ELK_SCHEME=${ELK_SCHEME:-"http"}
ELK_HOST=${ELK_HOST:-""}
ELK_PORT=${ELK_PORT:-"9200"}
export ELK_THREADS=${ELK_THREADS:-1}
export ELK_CONNECTION_HOST=${ELK_HOST:-"$ELK_CONTAINER_NAME"}

export MCP_ENDPOINT=${MCP_ENDPOINT:-"http://127.0.0.1:5158/mcp"}

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

log() { echo "[$(date +'%F %T')] $1"; }

# ============================================
# NGINX SSL SETUP
# ============================================
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

# ============================================
# REPLACE CSP LUA USING MARKERS
# ============================================
replace_csp_lua() {
    local NGINX_CONF="/etc/nginx/conf.d/onlyoffice.conf"

    # Add lua_shared_dict if missing
    if ! grep -q "lua_shared_dict csp_cache" "$NGINX_CONF"; then
        log "Adding lua_shared_dict csp_cache 10m to onlyoffice.conf"

        sed -i '/server_names_hash_bucket_size 128;/a\
    lua_shared_dict csp_cache 10m;
    ' "$NGINX_CONF"

        log "✅ lua_shared_dict added to onlyoffice.conf"
    else
        log "✅ lua_shared_dict already exists in onlyoffice.conf"
    fi

        if [[ ! -f "$NGINX_CONF" ]]; then
            log "⚠️ onlyoffice.conf not found at $NGINX_CONF"
            return 1
        fi
 
        log "🔧 Replacing Redis CSP Lua with shared_dict version"

    # Add lua_shared_dict if missing
    if [[ -f "$OPENRESTY_CONF" ]]; then
        if ! grep -q "lua_shared_dict csp_cache" "$OPENRESTY_CONF"; then
            log "Adding lua_shared_dict csp_cache 10m"
            sed -i '/^http {/a\    lua_shared_dict csp_cache 10m;' "$OPENRESTY_CONF"
            log "✅ lua_shared_dict added"
        else
            log "✅ lua_shared_dict already exists"
        fi
    fi

    # Verify markers exist
    if ! grep -q "# BEGIN_CSP_LUA" "$NGINX_CONF"; then
        log "❌ BEGIN_CSP_LUA marker not found"
        return 1
    fi

    if ! grep -q "# END_CSP_LUA" "$NGINX_CONF"; then
        log "❌ END_CSP_LUA marker not found"
        return 1
    fi

    # Create replacement block
    local TEMP_LUA
    TEMP_LUA=$(mktemp)

    cat > "$TEMP_LUA" <<'EOF'
# BEGIN_CSP_LUA
	access_by_lua '
		local accept = ngx.req.get_headers()["Accept"]

		if ngx.req.get_method() ~= "GET"
		   or not accept
		   or not string.find(accept, "html")
		   or ngx.re.match(ngx.var.request_uri, "ds-vpath|/api/")
		then
			return
		end

		local cache = ngx.shared.csp_cache
		local host  = ngx.var.host

		local cached = cache:get(host)
		if cached then
			ngx.header.Content_Security_Policy = cached
			return
		end

		local res = ngx.location.capture("/api/2.0/security/csp", {
			method = ngx.HTTP_GET
		})

		if res and res.status == 200 and res.body then
			local ok, data = pcall(require("cjson").decode, res.body)

			if ok and data and data.response and data.response.header then
				local header = data.response.header

				ngx.header.Content_Security_Policy = header
				cache:set(host, header, 15)

				ngx.log(ngx.INFO, "CSP cached for host: ", host)
			end
		end
	';
# END_CSP_LUA
EOF

    # Replace block between markers
    local TEMP_CONF
    TEMP_CONF=$(mktemp)

    LUA_FILE="$TEMP_LUA" perl -0777 -pe '
BEGIN {
    open my $fh, "<", $ENV{LUA_FILE} or die "Cannot open LUA_FILE: $!";
    local $/;
    $lua = <$fh>;
}
s/# BEGIN_CSP_LUA.*?# END_CSP_LUA/$lua/s;
' "$NGINX_CONF" > "$TEMP_CONF"

    if [[ $? -ne 0 ]]; then
        log "❌ Failed to replace CSP Lua block"
        rm -f "$TEMP_LUA" "$TEMP_CONF"
        return 1
    fi

    mv "$TEMP_CONF" "$NGINX_CONF"

    rm -f "$TEMP_LUA"

    # Verify replacement
    if grep -q "ngx.shared.csp_cache" "$NGINX_CONF"; then
        log "✅ CSP Lua successfully replaced"
        return 0
    else
        log "❌ CSP replacement verification failed"
        return 1
    fi
}

# ============================================
# MYSQL MIGRATION HELPERS
# ============================================
migration_count() {
    mysql "${MYSQL_ARGS[@]}" -sN -e "SELECT COUNT(*) FROM __EFMigrationsHistory;" \
        "$MYSQL_DATABASE" 2>/dev/null || echo "?"
}


# ============================================
# CONFIGURATION UPDATES
# ============================================
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
        -e "this.core.notify.postman='services'" \
        -e "this.ai.mcp[0].endpoint=process.env.MCP_ENDPOINT"

    # API system (connection + core)
    ${JSON} "${PATH_TO_CONF}/apisystem.json" \
        -e "this.ConnectionStrings.default.connectionString=process.env.CONNECTION_STRING+';Pooling=true;Character Set=utf8;AutoEnlist=false;SSL Mode=none;ConnectionReset=false;AllowPublicKeyRetrieval=true'" \
        -e "this.core['base-domain']=process.env.APP_CORE_BASE_DOMAIN" \
        -e "this.core.machinekey=process.env.APP_CORE_MACHINEKEY"

    # Elastic/OpenSearch configuration
    ${JSON} "${PATH_TO_CONF}/elastic.json" \
        -e "this.elastic.Scheme=process.env.ELK_SCHEME" \
        -e "this.elastic.Host=process.env.ELK_CONNECTION_HOST" \
        -e "this.elastic.Port=process.env.ELK_PORT" \
        -e "this.elastic.Threads=process.env.ELK_THREADS"

    # OAuth redirect
    sed -i -E "s!\"https://service\.teamlab\.info/oauth2\.aspx\"!\"${OAUTH_REDIRECT_URL}\"!g" "${PATH_TO_CONF}/autofac.consumers.json"
    # Migration runner connection string
    sed -i -E "s!(\"ConnectionString\").*!\1: \"${CONNECTION_STRING//!/\\!};Command Timeout=${COMMAND_TIMEOUT}\"!g" "${BACKEND_PATH}/appsettings.runner.json"

    log "✅ Configuration files updated"
}

# ============================================
# DATABASE MIGRATIONS
# ============================================
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

# ============================================
# MAIN
# ============================================
main() {
    echo "🚀 Starting Docker entrypoint..."
    echo "=================================="
    log "=== Starting initialization ==="
    update_configs
    run_migrations || { log "❌ Migration failed - exiting"; exit 1; }
    # Replace Redis Lua with shared_dict version 
    replace_csp_lua
    setup_nginx_ssl
    log "🌐 Initializing nginx..." && /nginx/docker-entrypoint.sh
    log "✅ Initialization complete - starting supervisord"
    log "=================================="
    exec supervisord -n
}

main

