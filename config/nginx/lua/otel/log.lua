-- log: emit an OTLP log record for the request (correlated with the server
-- span when tracing is on) and close the span with the response status.
local conf = require("otel.config")

if not (conf.traces_enabled or conf.logs_enabled) then
    return
end

local span = ngx.ctx.otel_span
ngx.ctx.otel_span = nil

local status = tonumber(ngx.var.status) or 0

-- path only, without the query string (it may carry tokens/session ids)
local path = ngx.var.request_uri:match("^[^?]*") or ngx.var.request_uri

if conf.logs_enabled then
    local severity_number, severity_text = 9, "INFO"
    if status >= 500 then
        severity_number, severity_text = 17, "ERROR"
    elseif status >= 400 then
        severity_number, severity_text = 13, "WARN"
    end

    local record = {
        timeUnixNano = string.format("%.0f", ngx.now() * 1e9),
        severityNumber = severity_number,
        severityText = severity_text,
        body = { stringValue = ngx.var.request_method .. " " .. path .. " " .. status },
        attributes = {
            { key = "http.request.method", value = { stringValue = ngx.var.request_method } },
            { key = "url.path", value = { stringValue = path } },
            { key = "http.response.status_code", value = { intValue = tostring(status) } },
            { key = "http.response.body.size", value = { intValue = tostring(tonumber(ngx.var.body_bytes_sent) or 0) } },
            { key = "http.server.request.duration", value = { doubleValue = tonumber(ngx.var.request_time) or 0 } },
            { key = "client.address", value = { stringValue = ngx.var.remote_addr or "" } },
            { key = "user_agent.original", value = { stringValue = ngx.var.http_user_agent or "" } },
            { key = "server.address", value = { stringValue = ngx.var.http_host or "" } },
        },
    }
    if span then
        local span_context = span:context()
        record.traceId = span_context.trace_id
        record.spanId = span_context.span_id
        record.flags = 1
    end
    require("otel.logs").emit(record)
end

if span then
    local attribute = require("opentelemetry.attribute")
    local span_status = require("opentelemetry.trace.span_status")
    span:set_attributes(attribute.int("http.status_code", status))
    if status >= 500 then
        span:set_status(span_status.ERROR, "HTTP " .. status)
    end
    span:finish()
end
