-- Carries the server span from the rewrite phase to the log phase.
--
-- Neither ngx.ctx nor $request_id can do this: both are reset on internal
-- redirects, and the router does those constantly (try_files falling back to
-- /index.html, the @wrong_*_chunk named locations). Losing the span there means
-- it is never finished, so it is never exported and the request log record
-- loses its trace correlation.
--
-- Request headers do survive an internal redirect, and the rewrite phase
-- already injects the span's own W3C traceparent into them, so that value is
-- used as the key. It identifies exactly one span by construction.
local _M = {}

local spans = {}

local function key()
    local traceparent = ngx.req.get_headers()["traceparent"]
    -- a repeated header arrives as a table of values; only the single one this
    -- module injects itself identifies a span, so anything else is not a key
    if type(traceparent) ~= "string" then
        return nil
    end
    return traceparent
end

-- Must be called after the propagator injected the context, otherwise there is
-- no header to key on yet.
function _M.set(span)
    local id = key()
    if id then
        spans[id] = span
    end
end

function _M.get()
    local id = key()
    if not id then
        return nil
    end
    return spans[id]
end

-- Returns the span and forgets it. The log phase runs exactly once per request,
-- so taking the span there keeps the registry from growing.
function _M.take()
    local id = key()
    if not id then
        return nil
    end
    local span = spans[id]
    spans[id] = nil
    return span
end

return _M
