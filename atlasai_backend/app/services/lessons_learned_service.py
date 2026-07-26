"""
Day 5: similarity search over historical incident reports.

Reuses the same ChromaDB 'documents' collection Day 2 ingestion already
writes to (filtered by doc_type == 'incident') rather than standing up a
separate store — one corpus, filtered by metadata, is simpler to keep
consistent than maintaining two.
"""
from typing import List, Dict, Any, Optional

from app.services.chroma_client import get_documents_collection
from app.services import embeddings

# Tuned for the current embedder (multi-qa-MiniLM-L6-cos-v1, unit-normalized
# vectors on ChromaDB's default l2/squared-euclidean space, where
# cos_sim = 1 - dist/2). Retune if the embedder changes.
SIMILARITY_THRESHOLD = 0.35


def _distance_to_similarity(distance: float) -> float:
    return max(0.0, min(1.0, 1 - (distance / 2)))


async def find_similar_incidents(
    query_text: str,
    exclude_doc_id: Optional[str] = None,
    top_k: int = 5,
) -> List[Dict[str, Any]]:
    """Returns past incident-classified chunks similar to query_text,
    deduplicated to one match per source document, sorted by similarity
    descending, above SIMILARITY_THRESHOLD.

    Note: async because embeddings.embed() is (it runs the model in a
    worker thread via asyncio.to_thread) — call sites must await this.
    """
    collection = get_documents_collection()
    query_vec = await embeddings.embed(query_text)

    try:
        results = collection.query(
            query_embeddings=[query_vec],
            n_results=top_k + 8,  # over-fetch since we dedupe per-document after
            where={"doc_type": "incident"},
        )
    except Exception:
        # Filtered query unsupported/failed for some reason — fail to an
        # empty match list rather than raising, this is a "no matches
        # found" outcome from the caller's point of view, not an error.
        return []

    ids = results.get("ids", [[]])[0]
    docs = results.get("documents", [[]])[0]
    metadatas = results.get("metadatas", [[]])[0]
    distances = results.get("distances", [[]])[0]

    matches: List[Dict[str, Any]] = []
    seen_docs = set()

    for doc_text, meta, dist in zip(docs, metadatas, distances):
        doc_id = meta.get("doc_id")
        if exclude_doc_id and doc_id == exclude_doc_id:
            continue
        if doc_id in seen_docs:
            continue

        similarity = _distance_to_similarity(dist)
        if similarity < SIMILARITY_THRESHOLD:
            continue

        seen_docs.add(doc_id)
        matches.append({
            "docId": doc_id,
            "fileName": meta.get("file_name"),
            "equipmentId": meta.get("equipment_id") or None,
            "similarity": round(similarity, 3),
            "snippet": doc_text[:220],
        })
        if len(matches) >= top_k:
            break

    matches.sort(key=lambda m: m["similarity"], reverse=True)
    return matches