"""
AtlasAI — Day 4: Knowledge Graph API routes

Mount in main.py with:
    from app.routers import graph as graph_router
    app.include_router(graph_router.router, prefix="/graph", tags=["knowledge-graph"])

Safe to mount even without Firestore credentials configured — every
route delegates to `knowledge_graph`, which degrades gracefully
(see knowledge_graph.py) rather than raising.
"""
from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel

from app.services.knowledge_graph import knowledge_graph

router = APIRouter()


class EdgeIn(BaseModel):
    from_type: str
    from_id: str
    to_type: str
    to_id: str
    relation: str
    bidirectional: bool = False


@router.post("/edge")
def create_edge(edge: EdgeIn):
    edge_id = knowledge_graph.add_edge(
        edge.from_type, edge.from_id, edge.to_type, edge.to_id, edge.relation, edge.bidirectional
    )
    return {"edge_id": edge_id, "created": edge_id is not None}


@router.get("/related/{node_type}/{node_id}")
def get_related(node_type: str, node_id: str, relation: Optional[str] = None):
    edges = knowledge_graph.get_related(node_type, node_id, relation=relation)
    return {
        "node_type": node_type,
        "node_id": node_id,
        "edges": [e.to_dict() | {"edge_id": e.edge_id} for e in edges],
    }


@router.get("/equipment/{equipment_tag}/people")
def people_for_equipment(equipment_tag: str):
    return {
        "equipment_tag": equipment_tag,
        "people": knowledge_graph.technicians_for_equipment(equipment_tag),
    }