from typing import Any, Dict, Optional
import os
import time

from app.services import embeddings, ingestion
from app.services.chroma_client import get_documents_collection
from app.telemetry import tracer
from app.otel_metrics import retrieval_duration_ms, chroma_query_duration_ms


def _distance_to_confidence(distance: float) -> float:
    cos_sim = 1 - distance / 2
    return max(0.0, min(1.0, cos_sim))


# Raw cosine similarity from this embedder (a MiniLM-class bi-encoder)
# rarely exceeds ~0.5-0.6 even for a genuinely correct, well-grounded
# match — averaging it directly and showing it as a percentage reads as
# "low confidence" for answers that are actually right. This is exactly
# what showed up in testing: correct, well-cited VALVE-12 answers
# scoring 37-39%.
#
# Rescale the raw average into a more representative 0-100% range using
# two tunable anchors instead of exposing the raw number directly.
# Tune via .env if this embedding model's typical range differs on your
# corpus — same pattern as CONFIDENCE_TEMPERATURE in knowledge_agent.py:
#   CONFIDENCE_LOW_ANCHOR  — raw cos_sim treated as ~0% confidence
#   CONFIDENCE_HIGH_ANCHOR — raw cos_sim treated as ~100% confidence
_LOW_ANCHOR = float(os.getenv("CONFIDENCE_LOW_ANCHOR", "0.15"))
_HIGH_ANCHOR = float(os.getenv("CONFIDENCE_HIGH_ANCHOR", "0.55"))


def _rescale_confidence(raw: float) -> float:
    if _HIGH_ANCHOR <= _LOW_ANCHOR:
        return raw  # misconfigured anchors — fall back to raw rather than divide by zero
    scaled = (raw - _LOW_ANCHOR) / (_HIGH_ANCHOR - _LOW_ANCHOR)
    return max(0.0, min(1.0, scaled))


async def retrieve(
    query: str,
    equipment_id: Optional[str] = None,
    n_results: int = 8,
    top_k: int = 5,
    require_equipment_match: bool = False,
) -> Dict[str, Any]:
    retrieve_start = time.perf_counter()
    with tracer.start_as_current_span(
        "retrieval.retrieve", attributes={"atlasai.query": query}
    ) as retrieve_span:
        collection = get_documents_collection()

        count = collection.count()
        if count == 0:
            retrieval_duration_ms.record(
                (time.perf_counter() - retrieve_start) * 1000, {"outcome": "empty_corpus"}
            )
            return {
                "top": [],
                "context_block": "",
                "sources": [],
                "confidence": 0.0,
                "tags": set(),
            }

        query_vec = await embeddings.embed(query)

        chroma_start = time.perf_counter()
        with tracer.start_as_current_span("chroma.query") as query_span:
            results = collection.query(
                query_embeddings=[query_vec],
                n_results=min(n_results, count),
                include=["documents", "metadatas", "distances"],
            )
            query_span.set_attribute("atlasai.chroma.n_results", min(n_results, count))
        chroma_query_duration_ms.record((time.perf_counter() - chroma_start) * 1000)

        docs = results["documents"][0]
        metas = results["metadatas"][0]
        dists = results["distances"][0]

        tags = set(tag.upper() for tag in ingestion.extract_equipment_tags(query))

        if equipment_id:
            tags.add(equipment_id.upper())

        ranked = list(zip(docs, metas, dists))

        if tags:
            matched = [
                item
                for item in ranked
                if item[1].get("equipment_id", "").upper() in tags
            ]

            if matched:
                ranked = matched

        top = ranked[:top_k]

        context_lines = []
        sources = []

        for i, (doc_text, meta, _) in enumerate(top, start=1):
            context_lines.append(f"[{i}] {doc_text}")

            sources.append(
                f"{meta.get('file_name', 'unknown')} (page {meta.get('page', '?')})"
            )

        scores = sorted(
            [_distance_to_confidence(d) for _, _, d in top],
            reverse=True,
        )

        raw_confidence = (
            sum(scores[:3]) / min(len(scores), 3)
            if scores
            else 0.0
        )
        confidence = _rescale_confidence(raw_confidence)

        retrieve_span.set_attribute("atlasai.retrieval.top_k", len(top))
        retrieve_span.set_attribute("atlasai.retrieval.confidence", confidence)
        retrieval_duration_ms.record(
            (time.perf_counter() - retrieve_start) * 1000, {"outcome": "ok"}
        )

        return {
            "top": top,
            "context_block": "\n\n".join(context_lines),
            "sources": sources,
            "confidence": round(confidence, 2),
            "tags": tags,
        }