-- rewrite: start a server span and propagate W3C trace context to the
-- upstream; the span is finished (and logged) in the log phase.
local conf = require("otel.config")

if not conf.traces_enabled then
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

-- path only, without the query string (it may carry tokens/session ids)
local path = ngx.var.request_uri:match("^[^?]*") or ngx.var.request_uri

local new_context, span = global.tracer("onlyoffice-router"):start(upstream_context,
    ngx.var.request_method .. " " .. ngx.var.uri, {
    kind = span_kind.server,
    attributes = {
        attribute.string("http.method", ngx.var.request_method),
        attribute.string("http.target", path),
        attribute.string("http.host", ngx.var.http_host or ""),
        attribute.string("http.scheme", ngx.var.scheme),
        attribute.string("net.peer.ip", ngx.var.remote_addr or ""),
    },
})

propagator:inject(new_context, ngx.req)
ngx.ctx.otel_span = span
