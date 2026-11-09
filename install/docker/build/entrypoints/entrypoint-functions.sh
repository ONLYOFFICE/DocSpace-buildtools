#!/bin/bash
# Helpers sourced by the bash entrypoints, so every image quotes and maps the database settings the same way

# Wraps a connection string value in double quotes when it holds a separator or a quote, doubling the inner double quotes
quote_connection_value() {
    local value="$1"
    if [[ "$value" == *[\;\"\']* ]]; then value="\"${value//\"/\"\"}\""; fi
    printf '%s' "$value"
}

# Prints the Connector/J sslMode for a MYSQL_SSL_MODE value; none and preferred print nothing and keep the driver default
jdbc_ssl_mode() {
    case "${1,,}" in
        none|preferred) ;;
        required) printf 'REQUIRED' ;;
        verifyca) printf 'VERIFY_CA' ;;
        verifyfull) printf 'VERIFY_IDENTITY' ;;
        *) echo "MYSQL_SSL_MODE must be one of none, preferred, required, verifyca, verifyfull" >&2; return 1 ;;
    esac
}
