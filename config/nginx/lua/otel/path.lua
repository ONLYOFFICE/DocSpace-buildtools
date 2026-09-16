-- Request path helpers shared by the rewrite and log phases.
local _M = {}

-- Path without the query string (it may carry tokens/session ids). Falls back
-- to an empty path rather than erroring when the variables are unset, which
-- happens on internally generated requests.
function _M.request_path()
    local uri = ngx.var.request_uri or ngx.var.uri or ""
    return uri:match("^[^?]*") or uri
end

return _M
