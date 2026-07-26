"""
Custom metric instruments, all exported to SigNoz via app.telemetry's
meter provider. Import `from app.otel_metrics import ...` wherever a
number needs recording — never call app.telemetry directly for this.

These are the numbers the SigNoz dashboards (see docs/SIGNOZ.md) are
built on: agent latency/success, Chroma retrieval latency, embedding
latency, Groq LLM latency + token usage + failures, and OCR duration +
pages + fallback rate.
"""
from app.telemetry import meter

# --- Orchestrator / agents (one series per agent via the `agent`
# attribute passed at record time — see orchestrator.py) ---
agent_duration_ms = meter.create_histogram(
    "atlasai.agent.duration_ms",
    unit="ms",
    description="Time a single agent (knowledge/maintenance/compliance/"
    "lessons_learned/knowledge_capture) takes to handle a request.",
)
agent_requests_total = meter.create_counter(
    "atlasai.agent.requests_total",
    description="Agent invocations, tagged with agent name and outcome (ok/error).",
)

# --- Retrieval (Chroma + embeddings) ---
retrieval_duration_ms = meter.create_histogram(
    "atlasai.retrieval.duration_ms",
    unit="ms",
    description="End-to-end app.services.retrieval.retrieve() call, "
    "including the embed-the-query step and the Chroma query itself.",
)
chroma_query_duration_ms = meter.create_histogram(
    "atlasai.chroma.query_duration_ms",
    unit="ms",
    description="Time spent in collection.query() alone.",
)
embedding_duration_ms = meter.create_histogram(
    "atlasai.embedding.duration_ms",
    unit="ms",
    description="sentence-transformers encode() call duration.",
)
embedding_batch_size = meter.create_histogram(
    "atlasai.embedding.batch_size",
    description="Number of texts embedded in one encode() call.",
)

# --- LLM (Groq / Llama 3.3 70B) ---
llm_duration_ms = meter.create_histogram(
    "atlasai.llm.duration_ms",
    unit="ms",
    description="Groq chat_completion() call duration.",
)
llm_tokens_total = meter.create_counter(
    "atlasai.llm.tokens_total",
    description="Prompt + completion tokens, tagged by `kind` (prompt/completion).",
)
llm_failures_total = meter.create_counter(
    "atlasai.llm.failures_total",
    description="Groq calls that raised (timeout, 4xx/5xx, missing API key, etc.).",
)

# --- OCR / ingestion (app/services/ingestion.py) ---
ocr_page_duration_ms = meter.create_histogram(
    "atlasai.ocr.page_duration_ms",
    unit="ms",
    description="Per-page extract_pages() duration (text layer or OCR fallback).",
)
ocr_pages_total = meter.create_counter(
    "atlasai.ocr.pages_total",
    description="Pages processed, tagged by `method` (text_layer/ocr_fallback).",
)
ocr_failures_total = meter.create_counter(
    "atlasai.ocr.failures_total",
    description="Pages where OCR fallback raised or produced empty text.",
)
