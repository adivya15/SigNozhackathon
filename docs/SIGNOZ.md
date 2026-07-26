# AtlasAI × SigNoz — Observability Integration

This documents what was added for the **Agents of SigNoz** hackathon
("Build Your Own" track) and how to demo it.

## What actually exists in this repo (correcting an earlier review)

An earlier review of this project assumed AtlasAI's agents were
"Knowledge / OCR / Maintenance / Storage / Summarization." That's not
this codebase. The real orchestrator (`app/orchestrator.py`) routes
between five agents:

- `knowledge_agent` — the only one that LLM-synthesizes an answer
  (Groq / Llama 3.3 70B), grounded in Chroma retrieval
- `maintenance_agent` — failure/RCA-keyword routing
- `compliance_agent` — audit/regulation-keyword routing
- `lessons_learned_agent` — matches new incidents against historical ones
- `knowledge_capture_agent` — guided interview capture flow

OCR isn't a separate agent — it's a fallback path inside
`app/services/ingestion.py::extract_pages()`, used per-page only when
PyMuPDF's text layer comes back empty (scanned documents). There's no
separate "Storage Agent" or "Summarization Agent" in this codebase.
The instrumentation below is built around the real structure, not the
generic one.

## What was instrumented

| Layer | File | What SigNoz sees |
|---|---|---|
| Every HTTP request | `app/main.py` (`instrument_fastapi_app`) | Root trace per `/query`, `/ingest`, `/actions/generate`, etc. |
| Each agent | `app/orchestrator.py` | `agent.<name>` span per invocation, tagged with outcome (ok/error) and confidence |
| Retrieval | `app/services/retrieval.py` | `retrieval.retrieve` span wrapping a `chroma.query` child span |
| Embeddings | `app/services/embeddings.py` | `embeddings.encode` span, batch size |
| LLM calls | `app/services/groq_client.py` | `groq.chat_completion` span with model, tokens, temperature; outbound HTTP also auto-traced via `HTTPXClientInstrumentor` |
| OCR/ingestion | `app/services/ingestion.py` | Per-page span tagged `text_layer` or `ocr_fallback`, with failures counted separately |
| Logs | `app/telemetry.py` (`LoggingInstrumentor`) | App logs correlated with trace/span IDs |

So a judge asking "what happens when I ask a question" gets exactly
the trace tree the hackathon rules ask for:

```
POST /query
 └─ agent.knowledge_agent
     └─ retrieval.retrieve
         └─ chroma.query
     └─ groq.chat_completion
         └─ POST api.groq.com/... (auto-instrumented httpx span)
```

## Metrics available (`app/otel_metrics.py`)

- `atlasai.agent.duration_ms`, `atlasai.agent.requests_total` (by agent, outcome)
- `atlasai.retrieval.duration_ms`, `atlasai.chroma.query_duration_ms`
- `atlasai.embedding.duration_ms`, `atlasai.embedding.batch_size`
- `atlasai.llm.duration_ms`, `atlasai.llm.tokens_total` (by kind: prompt/completion), `atlasai.llm.failures_total`
- `atlasai.ocr.page_duration_ms`, `atlasai.ocr.pages_total` (by method: text_layer/ocr_fallback), `atlasai.ocr.failures_total`

## Dashboards to build in the SigNoz UI

These aren't created programmatically (SigNoz dashboards are built in
its UI/JSON — do this once SigNoz is running so you can see real
data). Recommended panels, grouped as separate dashboards:

**1. Request overview** — p50/p95/p99 latency and error rate on the
FastAPI auto-instrumented spans, split by route.

**2. Agent Dashboard** (the one likely to stand out — most teams
won't have multi-agent traces to show) — one panel per agent using
`atlasai.agent.duration_ms` and `atlasai.agent.requests_total`,
grouped by the `agent` attribute: latency and success rate for
`knowledge_agent`, `maintenance_agent`, `compliance_agent`,
`lessons_learned_agent`, `knowledge_capture_agent`.

**3. RAG pipeline** — `atlasai.retrieval.duration_ms`,
`atlasai.chroma.query_duration_ms`, `atlasai.embedding.duration_ms`,
queries/sec (rate of `retrieval.retrieve` spans).

**4. LLM** — `atlasai.llm.duration_ms` (avg + slowest), token usage
over time (`atlasai.llm.tokens_total` by kind), `atlasai.llm.failures_total`.

**5. OCR/Ingestion** — OCR fallback rate (`ocr_fallback` vs
`text_layer` share of `atlasai.ocr.pages_total`), `atlasai.ocr.page_duration_ms`,
`atlasai.ocr.failures_total`.

## Alerts to configure (2–3 minimum per the rules)

- `atlasai.retrieval.duration_ms` p95 > 3s → warns retrieval is slow
- `atlasai.llm.duration_ms` p95 > 5s → warns Groq latency is degrading
- `atlasai.agent.requests_total{outcome="error"}` rate > 0 over 5 min → any agent starting to fail
- Optional: `atlasai.ocr.failures_total` rate > 10% of `atlasai.ocr.pages_total`

## Still to do before submitting (infrastructure, not code)

1. Deploy SigNoz with Foundry and commit the resulting `casting.yaml`
   (+ `casting.yaml.lock`) to the repo, per the hackathon's
   reproducibility requirement.
2. Set `OTEL_EXPORTER_OTLP_ENDPOINT` (and `OTEL_EXPORTER_OTLP_HEADERS`
   if using SigNoz Cloud) in `.env` / Render's environment variables.
3. Build the dashboards above in the SigNoz UI once real traffic is
   flowing, and configure the alerts.
4. Wire in SigNoz's MCP server if going for that integration point —
   not covered by this code change.
5. Write the mandatory project blog and record the demo.
