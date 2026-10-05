-- Decides which requests are worth reporting.
--
-- The lua hooks are wired at the http level, so they run for every location the
-- router handles. A single DocSpace page load pulls in hundreds of chunks,
-- fonts and images served straight off disk by try_files; those spans say
-- nothing the access log does not and would bury the API traces while
-- overflowing the log queue. They are dropped here unless
-- OTEL_TRACE_STATIC_ASSETS is turned on.
local conf = require("otel.config")

local _M = {}

local STATIC_EXTENSIONS = {
    css = true, js = true, mjs = true, map = true, json = true, webmanifest = true,
    png = true, jpg = true, jpeg = true, gif = true, svg = true, ico = true,
    webp = true, avif = true, bmp = true,
    woff = true, woff2 = true, ttf = true, otf = true, eot = true,
    wasm = true, txt = true, xml = true,
}

-- Matches both /static/... and the per-app /<app>/_next/static/... trees, which
-- is why this is a substring test and not a prefix one. Handler endpoints keep
-- their .ashx extension out of the table above so they stay traced.
function _M.is_static(path)
    if path:find("/static/", 1, true) then
        return true
    end
    local extension = path:match("%.(%w+)$")
    return extension ~= nil and STATIC_EXTENSIONS[extension:lower()] == true
end

-- `status` is nil in the rewrite phase, where nothing is known about the
-- response yet. In the log phase a failing asset is still reported: broken app
-- chunks are a routine router problem (hence the @wrong_*_chunk locations) and
-- those records are rare enough not to matter for volume.
function _M.skip(path, status)
    if conf.trace_static_assets or not _M.is_static(path) then
        return false
    end
    return status == nil or status < 400
end

return _M
