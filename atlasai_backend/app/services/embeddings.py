"""
Embeddings — computed locally via sentence-transformers, not over the
network. The model is pre-downloaded into the Docker image at build
time (see Dockerfile), so there is zero network dependency at runtime.

This replaces the earlier HF Inference API approach, which was prone
to intermittent ConnectTimeout failures — dangerous for a live demo,
since a failed call silently degraded to a near-meaningless hash-based
embedding and tanked confidence scores unpredictably.

Same model as before (multi-qa-MiniLM-L6-cos-v1, tuned for asymmetric
question -> passage retrieval), same 384-dim output — this is a
drop-in replacement, nothing downstream (chroma_client.py,
knowledge_agent.py) needs to change.
"""
import asyncio
import time
from typing import List

from sentence_transformers import SentenceTransformer

from app.telemetry import tracer
from app.otel_metrics import embedding_duration_ms, embedding_batch_size

_model = None


def _get_model() -> SentenceTransformer:
    global _model
    if _model is None:
        # Already cached in the image from the Dockerfile RUN step,
        # so this just loads it into memory — no download happens here.
        _model = SentenceTransformer("sentence-transformers/multi-qa-MiniLM-L6-cos-v1")
    return _model


def _encode_sync(texts: List[str]) -> List[List[float]]:
    model = _get_model()
    vectors = model.encode(texts, normalize_embeddings=True, convert_to_numpy=True)
    return [vec.tolist() for vec in vectors]


async def embed_batch(texts: List[str]) -> List[List[float]]:
    with tracer.start_as_current_span(
        "embeddings.encode", attributes={"atlasai.embedding.batch_size": len(texts)}
    ):
        start = time.perf_counter()
        # encode() is CPU-bound and synchronous — run it in a worker thread
        # so it doesn't block the event loop while other requests are in flight.
        result = await asyncio.to_thread(_encode_sync, texts)
        embedding_duration_ms.record((time.perf_counter() - start) * 1000)
        embedding_batch_size.record(len(texts))
        return result


async def embed(text: str) -> List[float]:
    result = await embed_batch([text])
    return result[0]