"""
AtlasAI — Day 4: Knowledge Graph implementation

Implements the `graph_edges/{edgeId}` collection defined in SCHEMA.md:

    {
      fromType: "equipment" | "document" | "person" | "date",
      fromId: string,
      toType: "equipment" | "document" | "person" | "date",
      toId: string,
      relation: string   // e.g. "documented_by", "reported_by", "dated"
    }

Firestore is the store for hackathon scope (per SCHEMA.md).

IMPORTANT — lazy, fault-tolerant initialization:
This module does NOT create a firestore.Client() at import time. An
earlier draft did (`kg = KnowledgeGraph()` at module level in the
router file), which meant just importing the router — required by
main.py at startup — would crash the ENTIRE backend (including the
already-working /ingest and /query endpoints) if Firestore Admin
credentials (GOOGLE_APPLICATION_CREDENTIALS) weren't configured yet.

Here, the Firestore client is created lazily on first real use, and
every public method catches connection/credential failures and
degrades gracefully (returns empty results, logs a clear warning)
instead of raising. This means: if you haven't set up a service
account yet, your app still starts and runs normally — the Knowledge
Graph just quietly does nothing until credentials are added, rather
than taking down the whole demo.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Optional

logger = logging.getLogger("atlasai.knowledge_graph")

NodeType = str  # "equipment" | "document" | "person" | "date"

RELATIONS = {
    "documented_by",  # equipment -> document
    "authored_by",     # person -> document
    "dated",             # document -> date
    "handled_by",         # equipment -> person (co-occurrence)
    "serviced_on",         # equipment -> date (co-occurrence)
    "reported_by",           # incident -> person
    "affects",                 # incident -> equipment
    "references",                # document -> incident
    "similar_to",                  # incident -> incident (Day 5, Lessons Learned)
    "linked_to",                     # generic fallback
}


@dataclass
class Edge:
    from_type: NodeType
    from_id: str
    to_type: NodeType
    to_id: str
    relation: str
    edge_id: Optional[str] = None

    def to_dict(self) -> dict:
        return {
            "fromType": self.from_type,
            "fromId": self.from_id,
            "toType": self.to_type,
            "toId": self.to_id,
            "relation": self.relation,
        }

    @classmethod
    def from_doc(cls, doc) -> "Edge":
        d = doc.to_dict()
        return cls(
            from_type=d["fromType"],
            from_id=d["fromId"],
            to_type=d["toType"],
            to_id=d["toId"],
            relation=d["relation"],
            edge_id=doc.id,
        )


class KnowledgeGraph:
    """Thin wrapper over the `graph_edges` Firestore collection.
    Every public method is safe to call even if Firestore credentials
    aren't configured — it logs a warning once and returns an empty/
    no-op result instead of raising, so callers (routes, agents) never
    need their own try/except around this."""

    COLLECTION = "graph_edges"

    def __init__(self):
        self._db = None
        self._col = None
        self._unavailable = False  # set True after first failed connect attempt

    def _get_collection(self):
        if self._unavailable:
            return None
        if self._col is not None:
            return self._col
        try:
            from google.cloud import firestore  # imported lazily too
            self._db = firestore.Client()
            self._col = self._db.collection(self.COLLECTION)
            return self._col
        except Exception as e:
            self._unavailable = True
            logger.warning(
                "Firestore unavailable (%s: %s) — Knowledge Graph is running "
                "in no-op mode. Set GOOGLE_APPLICATION_CREDENTIALS to a "
                "service account JSON to enable it. /ingest and /query "
                "continue to work normally without it.",
                type(e).__name__, e,
            )
            return None

    # -- writes ---------------------------------------------------------

    def add_edge(
        self,
        from_type: NodeType,
        from_id: str,
        to_type: NodeType,
        to_id: str,
        relation: str,
        bidirectional: bool = False,
    ) -> Optional[str]:
        """Creates an edge, deduped on (fromType, fromId, toType, toId,
        relation). Returns the edge id, or None if Firestore is
        unavailable (no-op)."""
        col = self._get_collection()
        if col is None:
            return None

        if relation not in RELATIONS:
            relation = "linked_to"

        try:
            existing = (
                col.where("fromType", "==", from_type)
                .where("fromId", "==", from_id)
                .where("toType", "==", to_type)
                .where("toId", "==", to_id)
                .where("relation", "==", relation)
                .limit(1)
                .stream()
            )
            existing_doc = next(existing, None)
            if existing_doc is not None:
                edge_id = existing_doc.id
            else:
                edge = Edge(from_type, from_id, to_type, to_id, relation)
                _, ref = col.add(edge.to_dict())
                edge_id = ref.id

            if bidirectional:
                self.add_edge(to_type, to_id, from_type, from_id, relation, bidirectional=False)

            return edge_id
        except Exception as e:
            logger.warning("add_edge failed (%s: %s) — skipping this edge.", type(e).__name__, e)
            return None

    def add_edges_from_entities(
        self,
        document_id: str,
        equipment_tags: list,
        personnel: list,
        dates: list,
    ) -> int:
        """Seeds the graph from Day 4 entity extraction output. Returns
        the count of edges successfully created (0 if Firestore is
        unavailable — never raises)."""
        if self._get_collection() is None:
            return 0

        created = 0
        for tag in equipment_tags:
            if self.add_edge("equipment", tag, "document", document_id, "documented_by"):
                created += 1
        for person in personnel:
            name = person["name"] if isinstance(person, dict) else person
            if self.add_edge("person", name, "document", document_id, "authored_by"):
                created += 1
        for date in dates:
            if self.add_edge("document", document_id, "date", date, "dated"):
                created += 1

        # Co-occurrence edges: link equipment directly to personnel/dates
        # found in the same document (page-level granularity is handled
        # by the caller, which passes already-scoped entity lists).
        for tag in equipment_tags:
            for person in personnel:
                name = person["name"] if isinstance(person, dict) else person
                role = person.get("role", "handled_by") if isinstance(person, dict) else "handled_by"
                relation = role if role in RELATIONS else "handled_by"
                if self.add_edge("equipment", tag, "person", name, relation):
                    created += 1
            for date in dates:
                if self.add_edge("equipment", tag, "date", date, "serviced_on"):
                    created += 1

        return created

    # -- reads ------------------------------------------------------------

    def get_related(
        self,
        node_type: NodeType,
        node_id: str,
        relation: Optional[str] = None,
        direction: str = "both",
    ) -> list:
        """Core traversal, e.g.:
            kg.get_related("equipment", "PUMP-04", relation="handled_by")
            -> people who have handled Pump 4
        Returns [] if Firestore is unavailable — never raises."""
        col = self._get_collection()
        if col is None:
            return []

        results: list = []
        try:
            if direction in ("both", "outgoing"):
                q = col.where("fromType", "==", node_type).where("fromId", "==", node_id)
                if relation:
                    q = q.where("relation", "==", relation)
                results.extend(Edge.from_doc(d) for d in q.stream())

            if direction in ("both", "incoming"):
                q = col.where("toType", "==", node_type).where("toId", "==", node_id)
                if relation:
                    q = q.where("relation", "==", relation)
                results.extend(Edge.from_doc(d) for d in q.stream())
        except Exception as e:
            logger.warning("get_related failed (%s: %s) — returning empty.", type(e).__name__, e)
            return []

        return results

    def technicians_for_equipment(self, equipment_tag: str) -> list:
        edges = self.get_related("equipment", equipment_tag, relation="handled_by", direction="outgoing")
        return sorted({e.to_id for e in edges})

    def enrich_context(self, equipment_tags: list) -> dict:
        """Called by the Knowledge Agent before answering, to attach
        graph context on top of vector-search results. Returns {} for
        any tag if Firestore is unavailable — safe to call unconditionally."""
        context = {}
        for tag in equipment_tags:
            context[tag] = {
                "people": self.technicians_for_equipment(tag),
                "documents": sorted(
                    e.to_id for e in self.get_related("equipment", tag, relation="documented_by")
                ),
            }
        return context


# Module-level singleton — safe because __init__ does no I/O and no
# credential lookup happens until a method is actually called.
knowledge_graph = KnowledgeGraph()