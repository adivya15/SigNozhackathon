"""
Base interface every AtlasAI agent implements.
Day 1: stub only — real reasoning logic gets filled in on the day
each agent is built (see 7-Day Plan: Knowledge Agent Day 3,
Maintenance + Lessons Learned Day 5, Compliance + Capture Day 5-6).
"""
from abc import ABC, abstractmethod
from typing import Any, Dict


class BaseAgent(ABC):
    """Every agent takes a structured request and returns a structured
    response the Orchestrator can merge with other agents' outputs."""

    name: str = "base_agent"

    @abstractmethod
    async def handle(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """
        request: {
            "query": str,
            "context": dict,   # e.g. equipment_id, user_role, doc_ids
        }
        returns: {
            "agent": str,
            "answer": str,
            "confidence": float,   # 0-1, feeds the Explainable AI panel
            "sources": list[str],  # document/knowledge-graph references
            "reasoning": str,      # short trace of why this answer was given
        }
        """
        raise NotImplementedError
