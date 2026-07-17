-- rewrite: start a server span, propagate W3C trace context to the upstream
-- and expose trace/span ids to the access log ($otel_trace_id/$otel_span_id).
local conf = require("otel.config")

if not conf.enabled then
    return
end

-- rewrite phase may run again after an internal redirect
if ngx.ctx.otel_span then
    return
end

local attribute = require("opentelemetry.attribute")
local global = require("opentelemetry.global")
local span_kind = require("opentelemetry.trace.span_kind")
local context = require("opentelemetry.context").new()
local propagator = require("opentelemetry.trace.propagation.text_map.trace_context_propagator").new()

local upstream_context = propagator:extract(context, ngx.req)

local new_context, span = global.tracer("onlyoffice-router"):start(upstream_context,
    ngx.var.request_method .. " " .. ngx.var.uri, {
    kind = span_kind.server,
    attributes = {
        attribute.string("http.method", ngx.var.request_method),
        attribute.string("http.target", ngx.var.request_uri),
        attribute.string("http.host", ngx.var.http_host or ""),
        attribute.string("http.scheme", ngx.var.scheme),
        attribute.string("net.peer.ip", ngx.var.remote_addr or ""),
    },
})

propagator:inject(new_context, ngx.req)
ngx.ctx.otel_span = span

-- $otel_* variables are declared only in server blocks that include
-- server-otel.conf; elsewhere the assignment is a harmless no-op
local span_context = span:context()
pcall(function()
    ngx.var.otel_trace_id = span_context.trace_id
    ngx.var.otel_span_id = span_context.span_id
    ngx.var.otel_log = 1
end)
