# AtlasAI — Day 1 Data Schema Reference

Agreed contract between Flutter (Firestore) and FastAPI (ChromaDB + Knowledge Graph)
so both sides can build independently through the week without breaking integration.

## Firestore Collections

### `users/{uid}`
```
{
  email: string,
  role: "technician" | "engineer" | "manager" | "auditor",
  displayName: string,
  createdAt: timestamp
}
```
Populated: Day 4 (Auth)

### `documents/{docId}`
```
{
  fileName: string,
  storageUrl: string,
  uploadedBy: uid,
  uploadedAt: timestamp,
  status: "pending" | "ingested" | "failed",
  linkedEquipmentIds: [string]
}
```
Populated: Day 2 (Ingestion)

### `equipment/{equipmentId}`
```
{
  tag: string,            // e.g. "PUMP-04"
  name: string,
  criticality: "low" | "medium" | "high",
  knowledgeDecayScore: number   // 0-1, computed by backend
}
```
Populated: Day 4 (entity extraction), scored Day 6

### `knowledge_cards/{cardId}`
```
{
  equipmentId: string,
  capturedFrom: uid,       // senior engineer who gave the interview
  capturedVia: "voice" | "text",
  transcript: string,
  structuredSummary: string,
  createdAt: timestamp
}
```
Populated: Day 5-6 (Knowledge Capture Agent)

### `incidents/{incidentId}`
```
{
  equipmentId: string,
  description: string,
  reportedBy: uid,
  reportedAt: timestamp,
  matchedHistoricalIncidentIds: [string]   // filled by Lessons Learned Agent
}
```
Populated: Day 5 (Lessons Learned Agent)

### `compliance_flags/{flagId}`
```
{
  documentId: string,
  rule: string,
  deviation: string,
  severity: "low" | "medium" | "high",
  flaggedAt: timestamp
}
```
Populated: Day 6 (Compliance Agent)

### `graph_edges/{edgeId}`
Simplified Knowledge Graph representation (hackathon scope — swappable
for a real graph DB like Neo4j post-hackathon).
```
{
  fromType: "equipment" | "document" | "person" | "incident",
  fromId: string,
  toType: "equipment" | "document" | "person" | "incident",
  toId: string,
  relation: string   // e.g. "documented_by", "maintained_by", "similar_to"
}
```
Populated: Day 4 (Knowledge Graph implementation)

---

## FastAPI / Orchestrator Contract

### `POST /query`
Request:
```json
{
  "query": "What do I check first when Pump 4 vibrates?",
  "user_role": "technician",
  "equipment_id": "PUMP-04",
  "doc_ids": null,
  "agents": null
}
```
Response:
```json
{
  "query": "...",
  "results": [
    {
      "agent": "maintenance_agent",
      "answer": "...",
      "confidence": 0.0,
      "sources": [],
      "reasoning": "..."
    }
  ],
  "merged_answer": "...",
  "overall_confidence": 0.0
}
```

This shape does not change as agents go from stub → real implementation —
only the contents of `answer`, `confidence`, `sources`, and `reasoning`
get richer. Flutter can build UI against this contract starting Day 1.

## ChromaDB Collections (Day 2+)

- `documents` — chunked + embedded text, metadata: `{doc_id, equipment_id, page}`
- `knowledge_cards` — embedded knowledge-card summaries, metadata: `{card_id, equipment_id}`
- `incidents` — embedded incident descriptions, metadata: `{incident_id, equipment_id}`
