-- Minimal OTLP/HTTP logs exporter (opentelemetry-lua has no logs signal).
-- Records are queued per worker from the log phase and flushed in batches to
-- <OTEL_EXPORTER_OTLP_ENDPOINT>/v1/logs by a background timer, so the request
-- path never does any I/O. When the queue is full new records are dropped;
-- records still queued on worker shutdown are lost.
local cjson = require("cjson.safe")
local conf = require("otel.config")

local _M = {}

local MAX_QUEUE = 2048
local FLUSH_INTERVAL = 3 -- seconds

local queue = {}
local dropped = 0

function _M.emit(record)
    if #queue >= MAX_QUEUE then
        dropped = dropped + 1
        return
    end
    queue[#queue + 1] = record
end

local function flush(premature)
    if #queue == 0 then
        return
    end
    local records = queue
    queue = {}
    if dropped > 0 then
        ngx.log(ngx.WARN, "otel: dropped ", dropped, " log records (queue full)")
        dropped = 0
    end

    local payload = cjson.encode({
        resourceLogs = { {
            resource = { attributes = { {
                key = "service.name",
                value = { stringValue = conf.service_name },
            } } },
            scopeLogs = { {
                scope = { name = "onlyoffice-router" },
                logRecords = records,
            } },
        } },
    })

    local headers = {}
    for key, value in pairs(conf.headers) do
        headers[key] = value
    end
    -- force our encoding last: the shared conf.headers table gets a
    -- Content-Type: application/x-protobuf entry from the traces http_client
    headers["Content-Type"] = "application/json"

    local httpc = require("resty.http").new()
    httpc:set_timeout(3000)
    local res, err = httpc:request_uri(conf.endpoint .. "/v1/logs", {
        method = "POST",
        headers = headers,
        body = payload,
    })
    if not res then
        ngx.log(ngx.WARN, "otel: logs export failed: ", err)
    elseif res.status >= 300 then
        ngx.log(ngx.WARN, "otel: logs export failed: HTTP ", res.status,
            " body: ", res.body and res.body:sub(1, 256) or "")
    end
end

function _M.start_timer()
    local ok, err = ngx.timer.every(FLUSH_INTERVAL, flush)
    if not ok then
        ngx.log(ngx.ERR, "otel: failed to start logs flush timer: ", err)
    end
end

return _M
