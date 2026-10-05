-- Request path helpers shared by the rewrite and log phases.
local _M = {}

local MAX_ROUTE_LENGTH = 128

-- Path without the query string (it may carry tokens/session ids). Falls back
-- to an empty path rather than erroring when the variables are unset, which
-- happens on internally generated requests.
function _M.request_path()
    local uri = ngx.var.request_uri or ngx.var.uri or ""
    return uri:match("^[^?]*") or uri
end

-- Span names have to stay low cardinality or the tracing backend cannot group
-- anything, so collapse the segments that carry ids (numeric keys, guids) into
-- a placeholder. The exact path is kept in the http.target attribute.
function _M.route(path)
    if path == "" then
        return "/"
    end
    local route = path:gsub("/([^/]+)", function(segment)
        if segment:match("^%d+$")
            or segment:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
            return "/{id}"
        end
        return "/" .. segment
    end)
    if #route > MAX_ROUTE_LENGTH then
        -- paths carry raw UTF-8 (file and room names), and a span name split
        -- mid-sequence is invalid UTF-8 that the collector rejects, so back the
        -- cut off over any continuation bytes
        local cut = MAX_ROUTE_LENGTH
        while cut > 0 do
            local following = route:byte(cut + 1)
            if not following or following < 0x80 or following > 0xBF then
                break
            end
            cut = cut - 1
        end
        route = route:sub(1, cut) .. "..."
    end
    return route
end

return _M
