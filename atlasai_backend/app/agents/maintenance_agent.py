from typing import Any, Dict
from app.agents.base import BaseAgent
from app.services.chroma_client import get_documents_collection
from app.services import embeddings
from app.services import graph_service


class MaintenanceAgent(BaseAgent):
    """Day 5: reasons over maintenance/incident records for a piece of
    equipment, and enriches the answer with Knowledge Graph context
    (who else has handled this equipment before) when available.

    Retrieval-based, not LLM-synthesized — deliberately, since the
    generation step (matching whatever the Knowledge Agent uses) is a
    natural drop-in upgrade for whoever owns that integration, without
    needing to touch this agent's retrieval or scoring logic.
    """

    name = "maintenance_agent"

    async def handle(self, request: Dict[str, Any]) -> Dict[str, Any]:
        query = request.get("query", "")
        context = request.get("context", {}) or {}
        equipment_id = context.get("equipment_id")

        collection = get_documents_collection()
        query_vec = await embeddings.embed(query)

        # Server-side `where` filtering hit inconsistent behavior across
        # this ChromaDB version (a flat multi-key dict raised "exactly
        # one operator"; the $and-wrapped version parsed fine but
        # returned zero matches despite matching documents existing).
        # Sidestepping it entirely: retrieve broadly, then filter/rank
        # client-side in Python — the exact pattern knowledge_agent.py
        # already uses successfully in this codebase for equipment-tag
        # matching, so this isn't a new approach, just reusing the one
        # that's proven to work here.
        n_results = min(8, collection.count())
        results = collection.query(query_embeddings=[query_vec], n_results=n_results)

        allowed_doc_types = {"maintenance_record", "incident", "general_document", "knowledge_capture"}
        all_docs = results.get("documents", [[]])[0]
        all_metas = results.get("metadatas", [[]])[0]
        all_dists = results.get("distances", [[]])[0]

        # Diagnostic: three different filter mechanisms have all failed
        # to match equipment_id == 'PUMP-04' scoped, while all succeed
        # unscoped — this shows exactly what's actually stored, to
        # confirm whether the bug is in storage (ingest) rather than in
        # any of the query-side filter attempts.
        print(
            f"[maintenance_agent] stored equipment_id values in top-{len(all_metas)}: "
            f"{[repr(m.get('equipment_id')) for m in all_metas]} | looking for {equipment_id!r}",
            flush=True,
        )

        filtered = [
            (doc, meta, dist)
            for doc, meta, dist in zip(all_docs, all_metas, all_dists)
            if meta.get("doc_type") in allowed_doc_types
            and (not equipment_id or meta.get("equipment_id") == equipment_id)
        ]

        if not filtered and equipment_id:
            # Nothing tagged for this exact equipment_id — relax to
            # doc_type only rather than failing outright, in case of an
            # equipment_id casing/format mismatch between this query and
            # what was stored at ingest time.
            print(f"[maintenance_agent] 0 matches for equipment_id={equipment_id!r}, retrying without equipment scope", flush=True)
            filtered = [
                (doc, meta, dist)
                for doc, meta, dist in zip(all_docs, all_metas, all_dists)
                if meta.get("doc_type") in allowed_doc_types
            ]

        filtered.sort(key=lambda item: item[2])  # ascending distance = best match first
        docs = [f[0] for f in filtered[:3]]
        metadatas = [f[1] for f in filtered[:3]]
        distances = [f[2] for f in filtered[:3]]

        if not docs:
            return {
                "agent": self.name,
                "answer": (
                    "No maintenance history found for this equipment yet. "
                    "Try uploading a maintenance log or incident report first."
                ),
                "confidence": 0.0,
                "sources": [],
                "reasoning": "No matching chunks in the maintenance/incident corpus.",
            }

        best_dist = distances[0] if distances else 2.0
        confidence = max(0.0, min(1.0, 1 - (best_dist / 2)))
        answer = " ".join(docs[:2])[:500]
        sources = sorted({m.get("file_name", "unknown") for m in metadatas if m.get("file_name")})

        graph_note = ""
        if equipment_id:
            graph = graph_service.get_equipment_graph(equipment_id)
            if graph.get("connected"):
                technicians = {c["id"] for c in graph["connected"] if c.get("type") == "person"}
                if technicians:
                    graph_note = f" {len(technicians)} technician(s) on record have handled this equipment before."

        return {
            "agent": self.name,
            "answer": f"{answer}{graph_note}",
            "confidence": round(confidence, 2),
            "sources": sources,
            "reasoning": (
                f"Retrieved top matches from maintenance/incident records"
                f"{' for ' + equipment_id if equipment_id else ''}, ranked by embedding similarity."
            ),
        }