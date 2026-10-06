#!/bin/bash
set -euo pipefail

# Default values
PATH_TO_CONF=${PATH_TO_CONF:-"/app/onlyoffice/config"}
SRC_PATH=${SRC_PATH:-"/app/onlyoffice/src"}
BACKEND_PATH="${SRC_PATH}/publish/services/backend"
DEBUG_INFO=${DEBUG_INFO:-"false"}
APP_CORE_BASE_DOMAIN=${APP_CORE_BASE_DOMAIN:-"localhost"}
APP_URL_PORTAL=${APP_URL_PORTAL:-"http://127.0.0.1:8092"}
#: "${APP_CORE_MACHINEKEY:?APP_CORE_MACHINEKEY must be set}"

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
# ASC.Identity (Java) reads this; computed here rather than left to docker-compose.yml's own interpolation, which doesn't nest ${} inside a default anywhere else in the codebase.
export JDBC_URL="${MYSQL_HOST}:${MYSQL_PORT}"
MYSQL_DATABASE=${MYSQL_DATABASE:-"onlyoffice_apps"}
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
export AI_SERVICE_URL=${AI_SERVICE_URL:-"http://127.0.0.1:5051"}

MIGRATION_TYPE=${MIGRATION_TYPE:-"STANDALONE"}  # STANDALONE or SAAS

# Same rule as docker-entrypoint.py: the edition picks the appsettings.<edition>.json overlay (license type/path) unless ENV_EXTENSION names another one.
[[ -z "${ENV_EXTENSION:-}" || "${ENV_EXTENSION}" == "none" ]] && ENV_EXTENSION="${INSTALLATION_TYPE:-}"
ENV_EXTENSION="${ENV_EXTENSION,,}"
export ENV_EXTENSION="${ENV_EXTENSION:-none}"

APP_CORE_SERVER_ROOT=${APP_CORE_SERVER_ROOT:-""}
APP_KNOWN_PROXIES=${APP_KNOWN_PROXIES:-""}
APP_KNOWN_NETWORKS=${APP_KNOWN_NETWORKS:-""}
CERTBOT_DIRS=(--config-dir /etc/letsencrypt --work-dir /tmp/letsencrypt --logs-dir /var/log/onlyoffice/letsencrypt)

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
# CONFIGURE NLOG LEVEL
# ============================================
update_nlog_level() {
    if [ -n "${LOG_LEVEL:-}" ]; then
        NLOG_PATH="${PATH_TO_CONF}/nlog.config"

        if [ ! -f "$NLOG_PATH" ]; then
            log "nlog.config not found: $NLOG_PATH"
            return 1
        fi

        log "Updating NLog minlevel to ${LOG_LEVEL}"

        sed -i '/ZiggyCreatures/! s/minlevel="[A-Za-z0-9_]*"/minlevel="'"$LOG_LEVEL"'"/g' "$NLOG_PATH"
    fi
}

# ============================================
# CONFIGURE SECRETS
# ============================================
ensure_secret() {
    local var_name="$1"
    local length="${2:-32}"

    local secrets_dir="/app/onlyoffice/data/.secrets"
    local secret_file="${secrets_dir}/${var_name}"

    # Read current value from environment
    eval "local value=\${$var_name:-}"

    # 1. Environment variable has highest priority
    if [ -n "$value" ]; then
        log "Using $var_name from environment."
        return
    fi

    mkdir -p "$secrets_dir"

    # 2. Use saved value if present
    if [ -f "$secret_file" ]; then
        value="$(cat "$secret_file")"
        log "Using persisted $var_name."
    else
    # 3. Generate a new value
        value="$(openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "$length")"
        printf '%s' "$value" > "$secret_file"
        chmod 600 "$secret_file"
        log "Generated and persisted $var_name."
    fi

    export "$var_name=$value"
}

# ============================================
# NGINX SSL SETUP
# ============================================
setup_nginx_ssl() {
    mkdir -p /letsencrypt /etc/letsencrypt

    write_http_nginx_conf() {
        cp /app/onlyoffice/template/nginx/onlyoffice-proxy.conf \
            /etc/nginx/conf.d/onlyoffice-proxy.conf
    }

    write_ssl_nginx_conf() {
        local https_port="${EXTERNAL_PORT_HTTPS:-443}"
        local redirect_port=""
        if [[ ! "$https_port" =~ ^[0-9]+$ ]] || (( 10#$https_port < 1 || 10#$https_port > 65535 )); then
            log "Invalid EXTERNAL_PORT_HTTPS: $https_port"
            return 1
        fi
        (( 10#$https_port == 443 )) || redirect_port=":$((10#$https_port))"
        # Prefer the file pregenerated by apps-ssl-setup; otherwise regenerate it, it isn't a secret.
        [ -f /etc/ssl/certs/dhparam.pem ] || { [ -f /etc/nginx/certs/dhparam.pem ] && cp /etc/nginx/certs/dhparam.pem /etc/ssl/certs/dhparam.pem; } \
            || openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 || return 1
        # server_name isn't templated: the shared config matches any host (it's the sole HTTPS front end), same as the other deployment modes.
        SSL_CERTIFICATE="$1" \
        SSL_CERTIFICATE_KEY="$2" \
        SSL_REDIRECT_PORT="$redirect_port" \
        envsubst '${SSL_CERTIFICATE} ${SSL_CERTIFICATE_KEY} ${SSL_REDIRECT_PORT}' \
            < <(sed 's#https://$host$request_uri#https://$host${SSL_REDIRECT_PORT}$request_uri#' /app/onlyoffice/template/nginx/onlyoffice-proxy-ssl.conf) \
            > /etc/nginx/conf.d/onlyoffice-proxy.conf || return 1
    }

    parse_ssl_domains() {
        IFS=',' read -ra SSL_DOMAINS <<< "$SSL_DOMAIN"

        CERTBOT_DOMAIN_ARGS=()
        NGINX_SERVER_NAMES=""

        for domain in "${SSL_DOMAINS[@]}"; do
            domain="$(echo "$domain" | xargs)"

            if [[ -z "$domain" ]]; then
                continue
            fi

            CERTBOT_DOMAIN_ARGS+=("-d" "$domain")
            NGINX_SERVER_NAMES="${NGINX_SERVER_NAMES} ${domain}"
        done

        NGINX_SERVER_NAMES="$(echo "$NGINX_SERVER_NAMES" | xargs)"
        PRIMARY_SSL_DOMAIN="$(echo "${SSL_DOMAINS[0]}" | xargs)"

        if [[ -z "$PRIMARY_SSL_DOMAIN" || ${#CERTBOT_DOMAIN_ARGS[@]} -eq 0 ]]; then
            log "SSL_DOMAIN is empty or invalid"
            exit 1
        fi
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

        parse_ssl_domains

        if write_ssl_nginx_conf "$SSL_CERT_PATH" "$SSL_KEY_PATH"; then
            log "Using custom SSL certificate for: $NGINX_SERVER_NAMES"
        else
            log "Warning: failed to configure HTTPS for $NGINX_SERVER_NAMES; starting with HTTP only"
            write_http_nginx_conf
        fi
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

        parse_ssl_domains

        local cert_file="/etc/letsencrypt/live/$PRIMARY_SSL_DOMAIN/fullchain.pem"
        local key_file="/etc/letsencrypt/live/$PRIMARY_SSL_DOMAIN/privkey.pem"

        if [[ ! -f "$cert_file" || ! -f "$key_file" || "$LETSENCRYPT_FORCE_RENEW" == "true" ]]; then
            log "Requesting Let's Encrypt certificate for: $NGINX_SERVER_NAMES"
            log "Port 80 must be reachable from the Internet for all domains"

            local staging_arg=()
            local renew_arg=()

            [[ "$LETSENCRYPT_STAGING" == "true" ]] && staging_arg=(--staging)
            [[ "$LETSENCRYPT_FORCE_RENEW" == "true" ]] && renew_arg=(--force-renewal)

            # CERTBOT_DIRS: the default work/log dirs under /var are root-only, and this container never runs as root.
            if certbot certonly "${CERTBOT_DIRS[@]}" \
                --standalone \
                --preferred-challenges http \
                --http-01-port 80 \
                --non-interactive \
                --agree-tos \
                --email "$SSL_EMAIL" \
                "${CERTBOT_DOMAIN_ARGS[@]}" \
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
            log "Existing Let's Encrypt certificate found for $PRIMARY_SSL_DOMAIN"
        fi

        if write_ssl_nginx_conf "$cert_file" "$key_file"; then
            log "Using Let's Encrypt certificate for: $NGINX_SERVER_NAMES"
        else
            log "Warning: failed to configure HTTPS for $NGINX_SERVER_NAMES; starting with HTTP only"
            write_http_nginx_conf
        fi
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

    if [[ ! -f "$NGINX_CONF" ]]; then
        log "⚠️ onlyoffice.conf not found at $NGINX_CONF"
        return 1
    fi

    log "🔧 Replacing Redis CSP Lua with shared_dict version"

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
	if not cache then
		ngx.log(ngx.ERR, "csp_cache shared dict is not configured")
		return
	end

	local headers = ngx.req.get_headers()
	local host = ngx.var.host or ""
	local origin = headers["Origin"] or ""
	local referer = headers["Referer"] or ""

	local cache_key = host .. "|" .. origin .. "|" .. referer

	local cached = cache:get(cache_key)
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
			cache:set(cache_key, header, 3)

			ngx.log(ngx.INFO, "CSP cached for key: ", cache_key)
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

    # Same forwarded-headers trust as docker-entrypoint.py: this container's own network and loopback, plus APP_KNOWN_NETWORKS/APP_KNOWN_PROXIES.
    export KNOWN_NETWORKS_JSON KNOWN_PROXIES_JSON
    KNOWN_NETWORKS_JSON="$(node -e '
        const os = require("os");
        const toInt = (ip) => ip.split(".").reduce((acc, octet) => ((acc << 8) + Number(octet)) >>> 0, 0);
        const toIp = (num) => [24, 16, 8, 0].map((shift) => (num >>> shift) & 255).join(".");
        const networks = [];
        const address = Object.values(os.networkInterfaces()).flat().find((iface) => iface && iface.family === "IPv4" && !iface.internal);
        if (address) {
            const [ip, bits] = address.cidr.split("/");
            const mask = Number(bits) === 0 ? 0 : (~0 << (32 - Number(bits))) >>> 0;
            networks.push(`${toIp(toInt(ip) & mask)}/${bits}`);
        } else {
            networks.push("127.0.0.1/8");
        }
        const extra = (process.env.APP_KNOWN_NETWORKS || "").split(",").map((item) => item.trim()).filter(Boolean);
        console.log(JSON.stringify(networks.concat(extra)));
    ')"
    KNOWN_PROXIES_JSON="$(node -e '
        const extra = (process.env.APP_KNOWN_PROXIES || "").split(",").map((item) => item.trim()).filter(Boolean);
        console.log(JSON.stringify(["127.0.0.1"].concat(extra)));
    ')"
    ${JSON} "${PATH_TO_CONF}/appsettings.json" \
        -e "this.core.hosting.forwardedHeadersOptions.knownNetworks=JSON.parse(process.env.KNOWN_NETWORKS_JSON)" \
        -e "this.core.hosting.forwardedHeadersOptions.knownProxies=JSON.parse(process.env.KNOWN_PROXIES_JSON)"
    [ -n "${APP_CORE_SERVER_ROOT}" ] && ${JSON} "${PATH_TO_CONF}/appsettings.json" -e "this.core['server-root']=process.env.APP_CORE_SERVER_ROOT"

    # Docs Admin Panel link
    ${JSON} "${PATH_TO_CONF}/externalresources.json" \
        -e "this.externalresources.adminpanel.default.domain=\"${DOCUMENT_SERVER_URL_PUBLIC%/}/admin\""

    # API system (connection + core)
    ${JSON} "${PATH_TO_CONF}/apisystem.json" \
        -e "this.ConnectionStrings.default.connectionString=process.env.CONNECTION_STRING+';Pooling=true;Character Set=utf8;AutoEnlist=false;SSL Mode=none;ConnectionReset=false;AllowPublicKeyRetrieval=true'" \
        -e "this.core['base-domain']=process.env.APP_CORE_BASE_DOMAIN" \
        -e "this.core.machinekey=process.env.APP_CORE_MACHINEKEY" \
	-e "this.core.notify.postman='services'"

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

install_plugin() {
    local source_dir="$1" target_dir="$2" staging_dir="$(dirname "$2")/.$(basename "$2").tmp"

    rm -rf "${staging_dir}"
    cp -a "${source_dir}" "${staging_dir}" && rm -rf "${target_dir}" && mv "${staging_dir}" "${target_dir}" || { rm -rf "${staging_dir}"; return 1; }
}

maintain_plugins() {
    local release_dir="${BUILD_PATH:-/var/www}/studio/plugins"
    local user_dir="/app/onlyoffice/data/Studio/webplugins"
    local state_file="${user_dir}/.plugins.state"
    local -A installed_versions=()
    local plugin version release_path release_version

    [ -d "${release_dir}" ] || return 0
    log "Plugins maintenance started..."
    mkdir -p "${user_dir}"

    if [ -f "${state_file}" ]; then
        while read -r plugin version || [ -n "${plugin}" ]; do
            if [ -n "${plugin}" ] && [ -n "${version}" ]; then
                installed_versions["${plugin}"]="${version}"
            elif [ -n "${plugin}" ]; then
                log "Invalid line in ${state_file}: '${plugin}'"
            fi
        done < "${state_file}"
    fi

    for release_path in "${release_dir}"/*/; do
        release_path="${release_path%/}"
        plugin="$(basename "${release_path}")"
        [ -f "${release_path}/config.json" ] || continue
        release_version="$(node /usr/local/bin/json -f "${release_path}/config.json" version || true)"
        if [ -z "${release_version}" ]; then
            log "Skipping ${plugin}: no version in config.json"
            continue
        fi

        if [ -n "${installed_versions[${plugin}]+set}" ]; then
            if [ ! -d "${user_dir}/${plugin}" ]; then
                log "Removed by user: ${plugin}"
            elif [ "${installed_versions[${plugin}]}" != "${release_version}" ]; then
                log "Updating ${plugin}: ${installed_versions[${plugin}]} -> ${release_version}"
                if install_plugin "${release_path}" "${user_dir}/${plugin}"; then
                    installed_versions["${plugin}"]="${release_version}"
                else
                    log "Failed to update ${plugin}"
                fi
            fi
        else
            log "Installing new plugin: ${plugin}"
            if install_plugin "${release_path}" "${user_dir}/${plugin}"; then
                installed_versions["${plugin}"]="${release_version}"
            else
                log "Failed to install ${plugin}"
            fi
        fi
    done

    for plugin in "${!installed_versions[@]}"; do
        echo "${plugin} ${installed_versions[${plugin}]}"
    done > "${state_file}.tmp"
    mv "${state_file}.tmp" "${state_file}"
    log "Plugins maintenance finished."
}

# ============================================
# MAIN
# ============================================
main() {
    echo "🚀 Starting Docker entrypoint..."
    echo "=================================="
    log "=== Starting initialization ==="
    # Runs before the chown below, so the Studio tree it creates ends up owned by onlyoffice
    maintain_plugins
    # app_data/log_data are shared with onlyoffice-document-server, which re-chowns its own Data dir's inode to its "ds" user on every one of its own restarts (confirmed live, not recursive - only this one entry). onlyoffice is in Docs' group (Dockerfile), so chmod g+w here survives that indefinitely; skips Docs' own wopi keys, its private signing material.
    find /app/onlyoffice/data \( -name wopi_private.key -o -name wopi_public.key \) -prune -o -exec chown onlyoffice:onlyoffice {} +
    chmod g+w /app/onlyoffice/data
    chown onlyoffice:onlyoffice /var/log/onlyoffice
    chmod g+w /var/log/onlyoffice
    update_nlog_level
    ensure_secret APP_CORE_MACHINEKEY 32
    export SPRING_APPLICATION_SIGNATURE_SECRET="$APP_CORE_MACHINEKEY"
    ensure_secret SPRING_APPLICATION_ENCRYPTION_SECRET 32
    update_configs
    run_migrations || { log "❌ Migration failed - exiting"; exit 1; }
    # Replace Redis Lua with shared_dict version 
    replace_csp_lua
    setup_nginx_ssl
    log "🌐 Initializing nginx..." && /nginx/docker-entrypoint.sh

    # The Dockerfile already strips quic/http3 at build time when this openresty build lacks it; this is a second check in case that detection was wrong - better HTTPS without HTTP/3 than openresty crash-looping.
    if ! /usr/local/openresty/bin/openresty -t >/tmp/nginx-t.log 2>&1 && grep -qi 'quic\|http/3\|http3' /tmp/nginx-t.log; then
        log "openresty -t failed on HTTP/3, retrying without it:"
        cat /tmp/nginx-t.log
        sed -i -e '/quic/d' -e '/alt-svc/d' /etc/nginx/conf.d/onlyoffice-proxy.conf
        /usr/local/openresty/bin/openresty -t
    fi

    # Everything above ran as root and can leave nginx/openresty's own files root-owned: the router's init scripts (prepare-nginx-router.sh's sed -i) rewrite conf.d files, and openresty -t itself creates its configured error_log if missing - confirmed live, both broke openresty (runs as onlyoffice below) with "Permission denied" until fixed here, right before it starts. /etc/nginx/certs is excluded: it's the read-only certs bind mount (docker-compose.yml), chown there fails the whole command (EROFS) - the certs are already world-readable (644), so onlyoffice doesn't need to own them anyway.
    find /etc/nginx /var/log/nginx /var/log/openresty /usr/local/openresty -path /etc/nginx/certs -prune -o -exec chown onlyoffice:onlyoffice {} +

    # openresty -t above (as root) also creates the *_temp dirs owned by nobody:root mode 700, so onlyoffice workers fail to buffer large request bodies (chunked upload -> 500, "open() /tmp/client_temp/... failed (13: Permission denied)")
    find /tmp -maxdepth 1 \( -name client_temp -o -name proxy_temp_path -o -name fastcgi_temp -o -name uwsgi_temp -o -name scgi_temp \) -exec chown -R onlyoffice:onlyoffice {} +

    log "✅ Initialization complete - starting supervisord"
    log "=================================="
    exec supervisord -n
}

main

