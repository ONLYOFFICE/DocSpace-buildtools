-- Reads OpenTelemetry settings from the environment (see the `env` directives
-- in nginx.conf.template). Tracing stays off unless OTEL_TRACES_ENABLED=true
-- and an OTLP endpoint is configured.
local _M = {}

local function getenv(name)
    local value = os.getenv(name)
    if value == nil or value == "" then
        return nil
    end
    return value
end

local endpoint = getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
if endpoint then
    endpoint = endpoint:gsub("/+$", "")
end

-- W3C env var format: key1=value1,key2=value2
local headers = {}
local raw_headers = getenv("OTEL_EXPORTER_OTLP_HEADERS")
if raw_headers then
    for pair in raw_headers:gmatch("[^,]+") do
        local key, value = pair:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if key and key ~= "" then
            headers[key] = value
        end
    end
end

_M.enabled = getenv("OTEL_TRACES_ENABLED") == "true" and endpoint ~= nil
_M.endpoint = endpoint
_M.service_name = getenv("OTEL_SERVICE_NAME") or "onlyoffice-router"
_M.headers = headers

return _M
