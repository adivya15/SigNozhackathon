# Deploying SigNoz with Foundry

`casting.yaml` (repo root) declares the deployment; `foundryctl`
(Foundry's CLI) turns it into a running SigNoz stack.

## 1. Install foundryctl

Follow the official quickstart: https://github.com/SigNoz/foundry —
there's no separate download step to fake here, just follow whatever
their install script/binary release says for your OS.

## 2. Validate and deploy

```bash
cd ethack_genai-main          # repo root, where casting.yaml lives
foundryctl gauge -f casting.yaml   # checks Docker + Compose plugin are present
foundryctl cast  -f casting.yaml   # generates pours/deployment/compose.yaml and starts it
```

`cast` writes `casting.yaml.lock` next to `casting.yaml` once it
succeeds — that's the file the hackathon rules ask you to commit
alongside `casting.yaml`. Don't hand-write it; it's a checksum file
Foundry generates and re-validates on every `cast`/`forge` run, and
don't hand-edit anything under `pours/` since `forge` overwrites it.

Confirm it's up: `docker compose -f pours/deployment/compose.yaml ps`
should show every container `Up`, then open http://localhost:8080.

## 3. Point AtlasAI at it

Two ways to run the backend, pick one:

**Directly on the host** (`uvicorn app.main:app`, simplest for local
dev/demo): in `atlasai_backend/.env`, leave
`OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318` as-is.

**In its own container** (`docker compose up` inside
`atlasai_backend/`): already handled —
`atlasai_backend/docker-compose.yml` points at
`http://host.docker.internal:4318` with the `extra_hosts` entry
needed for that to resolve on Linux too.

## 4. Confirm telemetry is arriving

Hit the backend (`POST /query` with a sample question) a few times,
then in the SigNoz UI: Traces should show a root span per request with
`agent.<name>`, `retrieval.retrieve`, `chroma.query`, and
`groq.chat_completion` child spans; Dashboards → New Dashboard should
let you query `atlasai.*` metrics (see `docs/SIGNOZ.md` for which ones
to build panels from).

## 5. MCP server

`casting.yaml` sets `mcp.spec.enabled: true`, so Foundry also stands
up the SigNoz MCP server on `localhost:8000` alongside the main stack
— that's the "SigNoz MCP integration" scoring point covered on the
infra side. Point whatever MCP client you're using at it per SigNoz's
MCP Server docs; that part isn't something this repo's code needs to
change for.
