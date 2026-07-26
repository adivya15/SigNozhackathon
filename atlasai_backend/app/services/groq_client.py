import os
import time
import httpx

from app.telemetry import tracer
from app.otel_metrics import llm_duration_ms, llm_tokens_total, llm_failures_total

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
DEFAULT_MODEL = "llama-3.3-70b-versatile"


async def chat_completion(system_prompt: str, user_prompt: str, model: str = DEFAULT_MODEL) -> str:
    # Note: the outbound POST itself also becomes its own child span via
    # HTTPXClientInstrumentor (see app/telemetry.py) — this span adds the
    # AI-specific attributes (model, temperature, token usage) that the
    # generic HTTP instrumentation doesn't know about.
    with tracer.start_as_current_span(
        "groq.chat_completion", attributes={"atlasai.llm.model": model, "atlasai.llm.temperature": 0.2}
    ) as span:
        start = time.perf_counter()
        try:
            api_key = os.getenv("GROQ_API_KEY")
            if not api_key:
                raise RuntimeError("GROQ_API_KEY not set")

            async with httpx.AsyncClient(timeout=30.0) as client:
                res = await client.post(
                    GROQ_URL,
                    headers={"Authorization": f"Bearer {api_key}"},
                    json={
                        "model": model,
                        "messages": [
                            {"role": "system", "content": system_prompt},
                            {"role": "user", "content": user_prompt},
                        ],
                        "temperature": 0.2,
                    },
                )
                res.raise_for_status()
                data = res.json()

            usage = data.get("usage", {})
            if usage:
                llm_tokens_total.add(usage.get("prompt_tokens", 0), {"kind": "prompt", "model": model})
                llm_tokens_total.add(usage.get("completion_tokens", 0), {"kind": "completion", "model": model})
                span.set_attribute("atlasai.llm.prompt_tokens", usage.get("prompt_tokens", 0))
                span.set_attribute("atlasai.llm.completion_tokens", usage.get("completion_tokens", 0))

            return data["choices"][0]["message"]["content"]

        except Exception as e:
            llm_failures_total.add(1, {"model": model, "error": type(e).__name__})
            span.record_exception(e)
            raise
        finally:
            llm_duration_ms.record((time.perf_counter() - start) * 1000, {"model": model})
