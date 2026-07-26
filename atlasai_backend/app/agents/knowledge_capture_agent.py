from typing import Any, Dict
from app.agents.base import BaseAgent


class KnowledgeCaptureAgent(BaseAgent):
    """Runs guided voice/chat interviews that convert a senior engineer's
    tacit experience into structured knowledge cards. Built out Day 5-6."""

    name = "knowledge_capture_agent"

    async def handle(self, request: Dict[str, Any]) -> Dict[str, Any]:
        # TODO (Day 5-6): guided interview flow + structured knowledge-card output
        return {
            "agent": self.name,
            "answer": f"[stub] Knowledge Capture Agent received: {request.get('query')}",
            "confidence": 0.0,
            "sources": [],
            "reasoning": "Stub response — capture flow not yet implemented.",
        }
