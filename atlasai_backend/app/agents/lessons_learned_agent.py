from typing import Any, Dict
from app.agents.base import BaseAgent
from app.services import lessons_learned_service


class LessonsLearnedAgent(BaseAgent):
    """Day 5: finds historical incidents similar to the current query,
    via embedding similarity over incident-classified documents."""

    name = "lessons_learned_agent"

    async def handle(self, request: Dict[str, Any]) -> Dict[str, Any]:
        query = request.get("query", "")
        matches = await lessons_learned_service.find_similar_incidents(query, top_k=3)

        if not matches:
            return {
                "agent": self.name,
                "answer": "No similar historical incidents found.",
                "confidence": 0.0,
                "sources": [],
                "reasoning": "No incident-classified documents matched above the similarity threshold.",
            }

        top = matches[0]
        equipment_note = f" (equipment: {top['equipmentId']})" if top.get("equipmentId") else ""
        answer = (
            f"Found {len(matches)} similar past incident(s). "
            f"Most similar{equipment_note}: \u201c{top['snippet']}\u201d"
        )
        sources = sorted({m["fileName"] for m in matches if m.get("fileName")})

        return {
            "agent": self.name,
            "answer": answer,
            "confidence": round(top["similarity"], 2),
            "sources": sources,
            "reasoning": f"Matched against {len(matches)} historical incident report(s) via embedding similarity.",
        }