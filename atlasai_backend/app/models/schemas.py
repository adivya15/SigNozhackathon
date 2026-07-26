from typing import Any, Dict, List, Optional
from pydantic import BaseModel


class OrchestratorRequest(BaseModel):
    query: str
    user_role: Optional[str] = "technician"   # technician | engineer | manager | auditor
    equipment_id: Optional[str] = None
    doc_ids: Optional[List[str]] = None
    agents: Optional[List[str]] = None        # force specific agents; None = auto-route


class AgentResult(BaseModel):
    agent: str
    answer: str
    confidence: float
    sources: List[str] = []
    reasoning: str = ""


class OrchestratorResponse(BaseModel):
    query: str
    results: List[AgentResult]
    merged_answer: str
    overall_confidence: float
    # Day 4: filled in when request.equipment_id resolves to graph
    # neighbors — e.g. "Linked: 2 documents, 3 person/people." Empty
    # string if there's no equipment_id or no edges yet.
    graph_context: str = ""


class GraphEdgeOut(BaseModel):
    edgeId: str
    fromType: str
    fromId: str
    toType: str
    toId: str
    relation: str


class SimilarIncidentOut(BaseModel):
    docId: str
    fileName: Optional[str] = None
    equipmentId: Optional[str] = None
    similarity: float
    snippet: str


class IngestResponse(BaseModel):
    docId: str
    fileName: str
    status: str
    pageCount: int
    chunkCount: int
    equipmentTags: List[str]
    graphEdges: List[GraphEdgeOut]
    # Day 4:
    personnel: List[str] = []
    dates: List[str] = []
    docType: str = "general_document"
    graphPersistedToFirestore: bool = False
    # Day 5:
    similarIncidents: List[SimilarIncidentOut] = []
    alertSent: bool = False


class GraphNeighborsResponse(BaseModel):
    """Day 4 shape — used by GET /graph/{entity_type}/{entity_id}."""
    entityType: str
    entityId: str
    edgeCount: int
    neighbors: Dict[str, List[str]]
    edges: List[Dict[str, Any]]


class GraphQueryResponse(BaseModel):
    """Day 5 shape — used by GET /graph/{equipment_id}. Kept alongside
    GraphNeighborsResponse rather than replacing it: the Day 5 Flutter
    screens/maintenance_agent.py expect this flatter {connected: [...]}
    form specifically."""
    equipmentId: str
    connected: List[Dict[str, Any]]
    graphEnabled: bool


# --- Day 5: Knowledge Capture Agent ---

class CaptureQuestionsResponse(BaseModel):
    equipmentId: Optional[str] = None
    questions: List[str]


class CaptureAnswer(BaseModel):
    question: str
    answer: str


class CaptureSubmitRequest(BaseModel):
    equipment_id: Optional[str] = None
    technician_id: Optional[str] = None
    answers: List[CaptureAnswer]


class CaptureSubmitResponse(BaseModel):
    cardId: str
    structuredSummary: str
    stored: bool


# --- Day 6: AI Action Engine ---

class ActionGenerateRequest(BaseModel):
    action_type: str   # rca_report | maintenance_checklist | inspection_schedule | preventive_maintenance | audit_report
    query: Optional[str] = None
    equipment_id: Optional[str] = None
    user_role: Optional[str] = "technician"


class ActionGenerateResponse(BaseModel):
    actionType: str
    title: str
    content: str
    sources: List[str] = []
    confidence: float