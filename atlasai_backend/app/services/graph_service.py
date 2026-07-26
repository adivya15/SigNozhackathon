"""
Day 4 — Knowledge Graph, plus Day 5 compatibility aliases.

Day 2 only ever produced equipment -> document ("documented_by") edges,
built in-memory and returned in the ingest response but never persisted.

This is the "full Knowledge Graph implementation" the plan calls for:
linking equipment <-> SOPs <-> incidents <-> technicians <-> maintenance
records, persisted to Firestore's `graph_edges` collection (per
SCHEMA.md), plus a traversal function so the app can actually answer
"which technicians have handled Pump 4 before" — the example straight
out of the plan.

Day 5's maintenance_agent.py and main.py call this under different
names (`sync_edges_to_firestore`, `get_equipment_graph`) than the ones
built here on Day 4 (`persist_edges`, `get_neighbors`) — the two
functions at the bottom are thin aliases/reshapers so both naming
conventions work against the same underlying store, instead of having
two divergent graph implementations.
"""
import uuid
from typing import Any, Dict, List

from app.services import firebase_admin_client as fb

GRAPH_COLLECTION = "graph_edges"

# Maps a classified doc_type to the edge relation used when linking
# equipment -> document, so the relation itself carries meaning instead
# of every document being generically "documented_by".
DOC_TYPE_RELATION = {
    "sop": "governed_by_sop",
    "incident": "has_incident",
    "maintenance_record": "maintained_via",
    "manual": "documented_by",
    "compliance": "audited_by",
    "general_document": "documented_by",
}


def _edge(from_type: str, from_id: str, to_type: str, to_id: str, relation: str) -> Dict[str, Any]:
    return {
        "edgeId": str(uuid.uuid4()),
        "fromType": from_type,
        "fromId": from_id,
        "toType": to_type,
        "toId": to_id,
        "relation": relation,
    }


def build_full_graph_edges(
    doc_id: str,
    doc_type: str,
    equipment_tags: List[str],
    personnel: List[str],
) -> List[Dict[str, Any]]:
    """Builds every edge this document contributes to the graph:
    equipment <-> document (typed by doc_type), and equipment <-> person
    (typed by whether the doc is a maintenance record or something
    else) for every equipment tag / name pair found in the same doc.
    """
    edges: List[Dict[str, Any]] = []
    relation = DOC_TYPE_RELATION.get(doc_type, "documented_by")

    for tag in equipment_tags:
        edges.append(_edge("equipment", tag, "document", doc_id, relation))

    for name in personnel:
        # A person mentioned in a maintenance record actually worked on
        # the equipment; anywhere else (SOP author, auditor, etc.) they're
        # linked to the document, not claimed as having maintained it.
        edges.append(_edge("document", doc_id, "person", name, "authored_or_cited_by"))
        if doc_type == "maintenance_record":
            for tag in equipment_tags:
                edges.append(_edge("equipment", tag, "person", name, "maintained_by"))

    return edges


def persist_edges(edges: List[Dict[str, Any]]) -> bool:
    """Writes each edge to Firestore graph_edges/{edgeId}. Returns
    whether it reached real Firestore (vs. the in-memory fallback) —
    main.py surfaces this so a demo running without Firebase creds
    still knows its graph data isn't durable."""
    for edge in edges:
        fb.set_doc(GRAPH_COLLECTION, edge["edgeId"], edge)
    return fb.is_connected()


def get_neighbors(entity_type: str, entity_id: str) -> Dict[str, Any]:
    """Real graph traversal: every edge touching this entity, plus the
    neighbor entities grouped by type. This is what answers
    "which technicians have handled Pump 4 before" or
    "which SOPs reference this incident type" — the two examples from
    the plan's Knowledge Graph section.
    """
    edges = fb.query_where_either(GRAPH_COLLECTION, "fromId", "toId", entity_id)

    neighbors: Dict[str, List[str]] = {}
    for edge in edges:
        if edge["fromId"] == entity_id:
            other_type, other_id = edge["toType"], edge["toId"]
        else:
            other_type, other_id = edge["fromType"], edge["fromId"]
        neighbors.setdefault(other_type, [])
        if other_id not in neighbors[other_type]:
            neighbors[other_type].append(other_id)

    return {
        "entityType": entity_type,
        "entityId": entity_id,
        "edgeCount": len(edges),
        "neighbors": neighbors,
        "edges": edges,
    }


def graph_context_summary(equipment_id: str) -> str:
    """Short human-readable string for graph-enriched answers, e.g.
    'Linked: 2 SOPs, 1 incident, 3 technicians.' Empty string if the
    equipment has no graph edges yet."""
    result = get_neighbors("equipment", equipment_id)
    neighbors = result["neighbors"]
    if not neighbors:
        return ""

    labels = {"document": "document(s)", "person": "person/people", "incident": "incident(s)"}
    parts = [f"{len(ids)} {labels.get(t, t)}" for t, ids in neighbors.items()]
    return "Linked: " + ", ".join(parts) + "."


# --- Day 5 compatibility aliases ---
# maintenance_agent.py and main.py (as shipped in the Day 5 zip) call
# these two names directly. Kept as thin wrappers over the functions
# above rather than duplicating the graph logic.

def sync_edges_to_firestore(edges: List[Dict[str, Any]]) -> bool:
    """Alias for persist_edges — same thing, Day 5's naming."""
    return persist_edges(edges)


def get_equipment_graph(equipment_id: str) -> Dict[str, Any]:
    """Day 5 shape: {equipmentId, connected, graphEnabled}. Reshapes
    get_neighbors()'s edge list into a flat 'connected' list — each
    entry is {type, id, relation} — since that's what maintenance_agent.py
    and the GraphQueryResponse schema expect, vs. get_neighbors()'s
    richer {neighbors, edges} shape used elsewhere.
    """
    result = get_neighbors("equipment", equipment_id)
    connected = []
    for edge in result["edges"]:
        if edge["fromId"] == equipment_id:
            other_type, other_id = edge["toType"], edge["toId"]
        else:
            other_type, other_id = edge["fromType"], edge["fromId"]
        connected.append({"type": other_type, "id": other_id, "relation": edge["relation"]})

    return {
        "equipmentId": equipment_id,
        "connected": connected,
        "graphEnabled": fb.is_connected(),
    }