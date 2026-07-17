-- log: close the server span with the response status.
local conf = require("otel.config")

if not conf.enabled then
    return
end

local span = ngx.ctx.otel_span
if not span then
    return
end
ngx.ctx.otel_span = nil

local attribute = require("opentelemetry.attribute")
local span_status = require("opentelemetry.trace.span_status")

local status = tonumber(ngx.var.status) or 0
span:set_attributes(attribute.int("http.status_code", status))
if status >= 500 then
    span:set_status(span_status.ERROR, "HTTP " .. status)
end
span:finish()
