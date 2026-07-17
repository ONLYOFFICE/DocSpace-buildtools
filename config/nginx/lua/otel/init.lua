-- init_worker: set up the tracer provider exporting spans over OTLP/HTTP
-- to <OTEL_EXPORTER_OTLP_ENDPOINT>/v1/traces.
local conf = require("otel.config")

if not conf.enabled then
    return
end

local attribute = require("opentelemetry.attribute")
local global = require("opentelemetry.global")
local resource = require("opentelemetry.resource")
local tracer_provider = require("opentelemetry.trace.tracer_provider")
local batch_span_processor = require("opentelemetry.trace.batch_span_processor")
local otlp_exporter = require("opentelemetry.trace.exporter.otlp")
local http_client = require("opentelemetry.trace.exporter.http_client")
local always_on_sampler = require("opentelemetry.trace.sampling.always_on_sampler")

local exporter = otlp_exporter.new(http_client.new(conf.endpoint, 3, conf.headers))
-- never block request processing when the collector is unreachable
local processor = batch_span_processor.new(exporter, { drop_on_queue_full = true })

global.set_tracer_provider(tracer_provider.new(processor, {
    sampler = always_on_sampler.new(),
    resource = resource.new(attribute.string("service.name", conf.service_name)),
}))
