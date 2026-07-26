"""
OpenTelemetry wiring for AtlasAI -> SigNoz.

This module has side effects at import time (sets the global tracer
and meter providers), so it must be imported once, early, from
main.py — before any other app module that calls get_tracer()/get_meter()
or uses the `tracer`/`meter` objects below.

Env vars (see .env.example):
  OTEL_SERVICE_NAME              defaults to "atlasai-backend"
  OTEL_EXPORTER_OTLP_ENDPOINT    e.g. https://ingest.<region>.signoz.cloud:443
                                  (SigNoz Cloud) or http://localhost:4318
                                  (self-hosted SigNoz via Foundry/docker-compose)
  OTEL_EXPORTER_OTLP_HEADERS     e.g. "signoz-ingestion-key=<your-key>"
                                  (SigNoz Cloud only; omit for self-hosted)

Nothing here talks to SigNoz directly — the OTLP exporters read the
OTEL_EXPORTER_OTLP_* env vars themselves and ship traces/metrics/logs
to whatever collector endpoint is configured.
"""
import logging
import os

from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

SERVICE_NAME = os.getenv("OTEL_SERVICE_NAME", "atlasai-backend")

_resource = Resource.create({"service.name": SERVICE_NAME})

# --- Traces: every span created anywhere in the app goes through this
# provider and is batched off to SigNoz over OTLP/HTTP. ---
_trace_provider = TracerProvider(resource=_resource)
_trace_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(_trace_provider)

# --- Metrics: custom histograms/counters (agent latency, LLM tokens,
# OCR success rate, etc. — defined in otel_metrics.py) are exported on
# a 10s cadence. ---
_metric_reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(), export_interval_millis=10000
)
_meter_provider = MeterProvider(resource=_resource, metric_readers=[_metric_reader])
metrics.set_meter_provider(_meter_provider)

# --- Logs: correlate app logs with trace/span IDs so a SigNoz trace
# can jump straight to the log lines it produced. ---
LoggingInstrumentor().instrument(set_logging_format=True)
logging.basicConfig(level=logging.INFO)

# --- Auto-instrumentation for outbound HTTP (covers groq_client.py's
# httpx calls to the Groq API — each becomes its own child span with
# status code, duration, and URL as attributes, no manual span needed
# there beyond the token/latency metrics added in groq_client.py). ---
HTTPXClientInstrumentor().instrument()

tracer = trace.get_tracer(SERVICE_NAME)
meter = metrics.get_meter(SERVICE_NAME)


def instrument_fastapi_app(app) -> None:
    """Call once from main.py right after `app = FastAPI(...)`. Wraps
    every route so each incoming request becomes a root trace (this is
    what makes "every request should appear as a trace in SigNoz" true
    for /query, /ingest, /actions/generate, etc. with zero per-route
    code)."""
    FastAPIInstrumentor.instrument_app(app)
