# Building the SigNoz Dashboards & Alerts

Do this after `docs/FOUNDRY_DEPLOY.md` — you need real traffic hitting
the instrumented backend first (ingest a doc, ask a few questions
across different agent types) so the query builder has data to pick
from when you go looking for metric/attribute names.

Dashboards aren't scripted here (SigNoz's dashboard JSON schema is
version-specific enough that a hand-written import is more likely to
break than help) — build each one in the UI with **+ New Dashboard →
New Panel**, using the query builder as below. Five minutes each.

## 1. Request Overview

Uses the auto-instrumented FastAPI spans, not the custom metrics.

- **Panel: Request latency** — Data source: Traces. Aggregate: p50/p95/p99 of Duration. Group by `http.route`.
- **Panel: Error rate** — Data source: Traces. Aggregate: Count, filter `has_error = true`. Group by `http.route`.
- **Panel: Requests/sec** — Data source: Traces. Aggregate: Count (rate). Group by `http.route`.

## 2. Agent Dashboard ⭐

The differentiator — one row per agent using the `atlasai.agent.*` metrics.

- **Panel: Agent latency** — Metric: `atlasai.agent.duration_ms`. Aggregate: Avg (or p95). Group by `agent`. Panel type: Time series (one line per agent: knowledge_agent, maintenance_agent, compliance_agent, lessons_learned_agent, knowledge_capture_agent).
- **Panel: Agent success rate** — Metric: `atlasai.agent.requests_total`. Aggregate: Count. Group by `agent`, `outcome`. Panel type: Bar or stacked time series so `ok` vs `error` per agent is visible at a glance.
- **Panel: Agent call volume** — Same metric, Count, group by `agent` only. Panel type: Number/Table for a quick "which agent gets used most" read during the demo.

## 3. RAG Pipeline

- **Panel: Retrieval latency** — Metric: `atlasai.retrieval.duration_ms`. Aggregate: Avg + p95.
- **Panel: Chroma query latency** — Metric: `atlasai.chroma.query_duration_ms`. Aggregate: Avg.
- **Panel: Embedding latency** — Metric: `atlasai.embedding.duration_ms`. Aggregate: Avg.
- **Panel: Queries/sec** — Metric: `atlasai.retrieval.duration_ms`. Aggregate: Count (rate).

## 4. LLM Dashboard

- **Panel: LLM latency** — Metric: `atlasai.llm.duration_ms`. Aggregate: Avg + p95. Group by `model`.
- **Panel: Slowest queries** — Data source: Traces, span name `groq.chat_completion`. Sort by Duration desc. Panel type: Table (Top 10).
- **Panel: Token usage** — Metric: `atlasai.llm.tokens_total`. Aggregate: Sum. Group by `kind` (prompt/completion).
- **Panel: LLM failures** — Metric: `atlasai.llm.failures_total`. Aggregate: Count. Group by `error`.

## 5. OCR Dashboard

- **Panel: OCR fallback rate** — Metric: `atlasai.ocr.pages_total`. Aggregate: Count. Group by `method` (`text_layer` vs `ocr_fallback`) — the ratio of the two is your fallback rate.
- **Panel: OCR page duration** — Metric: `atlasai.ocr.page_duration_ms`. Aggregate: Avg. Group by `method`.
- **Panel: OCR failures** — Metric: `atlasai.ocr.failures_total`. Aggregate: Count. Group by `reason`.

## Alerts (need at least 2–3)

Alerts → New Alert → Metric-based, same query builder as above.

1. **Slow retrieval** — `atlasai.retrieval.duration_ms`, p95 over 5 min > 3000 (3s). Severity: Warning.
2. **Slow LLM** — `atlasai.llm.duration_ms`, p95 over 5 min > 5000 (5s). Severity: Warning.
3. **Agent errors** — `atlasai.agent.requests_total` filtered `outcome = error`, count over 5 min > 0. Severity: Critical.
4. *(optional)* **OCR failures** — `atlasai.ocr.failures_total` rate > 10% of `atlasai.ocr.pages_total` over 15 min.

For the notification channel, a webhook or email is enough to satisfy
the requirement — you don't need Slack wired up for the demo, showing
the alert *rule* firing in the SigNoz UI is enough (a live Slack ping
is a nice-to-have, not required).

## Demo-day tip

Right before recording, run a couple of deliberately slow/failing
requests (e.g. a very long document, or a question with no matching
context) so at least one panel shows a spike and, ideally, one alert
transitions to firing on camera — a flat, all-green dashboard is far
less convincing than one that visibly reacts to something.
