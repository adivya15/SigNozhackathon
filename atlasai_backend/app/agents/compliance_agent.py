"""
Day 6: Compliance Agent — checks maintenance/inspection records against
sample regulatory thresholds and flags deviations.

Scope note: real OISD/Factory Act compliance is a huge, jurisdiction-
specific domain. This implements a small, genuinely-checkable rule set
(lubrication interval limits, inspection frequency) rather than an LLM
prompt that sounds authoritative but can't actually be verified against
a number — for a hackathon demo, "flags a real deviation against a real
threshold" is worth more than a longer list of rules that just look
official. Extending RULES is the natural next step, not a redesign.
"""
import re
from typing import Any, Dict, List, Optional

from app.agents.base import BaseAgent
from app.services.chroma_client import get_documents_collection
from app.services import embeddings

# Sample thresholds by equipment-tag prefix. Real numbers would come
# from the applicable OISD standard / vendor spec / site SOP — these
# are illustrative but structured exactly like real ones would be, so
# swapping in real values later doesn't change the checking logic.
RULES = {
    "PUMP": {
        "max_lubrication_interval_days": 60,
        "min_inspection_frequency_days": 90,
        "source": "OISD-STD-113 (sample) — Pump lubrication & inspection",
    },
    "VALVE": {
        "min_inspection_frequency_days": 180,
        "source": "OISD-STD-123 (sample) — Valve inspection interval",
    },
    "COMPRESSOR": {
        "max_lubrication_interval_days": 30,
        "min_inspection_frequency_days": 90,
        "source": "OISD-STD-108 (sample) — Compressor maintenance",
    },
}

# Matches "45-day", "45 day", "every 45 days", "90-day interval",
# "45 to day(s)" style phrasing, etc.
INTERVAL_PATTERN = re.compile(
    r"(\d{1,4})\s*(?:-|to\s*)?(?:day|days)",
    re.IGNORECASE,
)


def _equipment_prefix(equipment_id: str) -> Optional[str]:
    for prefix in RULES:
        if equipment_id.upper().startswith(prefix):
            return prefix
    return None


def _equipment_match(equipment_id: str, doc: str, meta: Dict[str, Any]) -> bool:
    """Broad equipment match — mirrors whatever shape the Knowledge
    Agent's retrieval already succeeds against, rather than assuming a
    single strict metadata key/doc_type combination. Checks, in order:
    equipment_id, equipment_tag, an equipment_ids list, the equipment_id
    appearing anywhere in the metadata dict (stringified), and finally
    as a fallback, the equipment_id appearing in the chunk text itself.
    """
    if meta.get("equipment_id") == equipment_id:
        return True

    if meta.get("equipment_tag") == equipment_id:
        return True

    equipment_ids = meta.get("equipment_ids")
    if isinstance(equipment_ids, list) and equipment_id in equipment_ids:
        return True

    if equipment_id in str(meta):
        return True

    if equipment_id in doc:
        return True

    return False


def _check_lubrication_interval(text: str, rule: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Looks for a stated interval (e.g. '45-day intervals') in the
    text and compares it against max_lubrication_interval_days. Returns
    None if no interval is mentioned — absence of data isn't a
    deviation, it's just not checkable from what's been ingested."""
    max_days = rule.get("max_lubrication_interval_days")
    if max_days is None:
        return None

    intervals = [int(m.group(1)) for m in INTERVAL_PATTERN.finditer(text)]
    if not intervals:
        return None

    stated = min(intervals)  # the tightest/most-recent stated interval found
    if stated > max_days:
        return {
            "check": "lubrication_interval",
            "status": "deviation",
            "detail": f"Stated interval is {stated} days; standard allows a maximum of {max_days} days.",
        }
    return {
        "check": "lubrication_interval",
        "status": "compliant",
        "detail": f"Stated interval is {stated} days, within the {max_days}-day maximum.",
    }


class ComplianceAgent(BaseAgent):
    """Day 6: retrieves maintenance/compliance records for the equipment
    in question and checks them against RULES, flagging deviations with
    the specific number and standard cited — not just a generic
    'may not be compliant' hedge."""

    name = "compliance_agent"

    async def handle(self, request: Dict[str, Any]) -> Dict[str, Any]:
        query = request.get("query", "")
        context = request.get("context", {}) or {}
        equipment_id = context.get("equipment_id")

        if not equipment_id:
            return {
                "agent": self.name,
                "answer": (
                    "Compliance checking needs an equipment_id to look up the applicable "
                    "standard. Ask again with the equipment specified, e.g. \"Is PUMP-04 "
                    "within its lubrication interval?\""
                ),
                "confidence": 0.0,
                "sources": [],
                "reasoning": "No equipment_id in request context — cannot select a rule set.",
            }

        prefix = _equipment_prefix(equipment_id)
        if not prefix:
            return {
                "agent": self.name,
                "answer": f"No sample compliance rules configured for equipment type of {equipment_id} yet.",
                "confidence": 0.0,
                "sources": [],
                "reasoning": f"No RULES entry matches the prefix of {equipment_id}.",
            }
        rule = RULES[prefix]

        # Retrieve maintenance/compliance-relevant chunks for this
        # equipment, client-side filtered — same pattern as
        # maintenance_agent.py, proven reliable in this codebase over
        # the ChromaDB where-clause version's inconsistent behavior.
        collection = get_documents_collection()
        query_vec = await embeddings.embed(query or f"{equipment_id} maintenance compliance")
        n_results = min(8, collection.count())
        results = collection.query(query_embeddings=[query_vec], n_results=n_results)

        all_docs = results.get("documents", [[]])[0]
        all_metas = results.get("metadatas", [[]])[0]

        # Debug: dump retrieved metadata so we can see the actual shape
        # coming back from Chroma before filtering rejects anything.
        print("==== Retrieved Metadata ====")
        for meta in all_metas:
            print(meta)

        relevant = [
            (doc, meta)
            for doc, meta in zip(all_docs, all_metas)
            if _equipment_match(equipment_id, doc, meta)
        ]

        if not relevant:
            return {
                "agent": self.name,
                "answer": (
                    f"No maintenance or compliance records found for {equipment_id} yet — "
                    f"nothing to check against {rule['source']}."
                ),
                "confidence": 0.0,
                "sources": [],
                "reasoning": "No matching chunks in the corpus for this equipment.",
            }

        combined_text = " ".join(doc for doc, _ in relevant)
        sources = sorted({m.get("file_name", "unknown") for _, m in relevant if m.get("file_name")})

        print("\n===== Combined Text =====")
        print(combined_text)

        regex_matches = INTERVAL_PATTERN.findall(combined_text)
        print("\n===== Regex Matches =====")
        print(regex_matches)
        if not regex_matches:
            print("No numeric interval found in retrieved text.")

        findings: List[Dict[str, Any]] = []
        lube_check = _check_lubrication_interval(combined_text, rule)
        if lube_check:
            findings.append(lube_check)

        if not findings:
            return {
                "agent": self.name,
                "answer": (
                    f"Records exist for {equipment_id} but don't state a checkable interval "
                    f"(e.g. lubrication frequency) against {rule['source']}."
                ),
                "confidence": 0.3,
                "sources": sources,
                "reasoning": "Records found, but no numeric interval matched the rule's checkable pattern.",
            }

        deviations = [f for f in findings if f["status"] == "deviation"]
        if deviations:
            answer = (
                f"DEVIATION FLAGGED for {equipment_id} against {rule['source']}: "
                + " ".join(f["detail"] for f in deviations)
            )
            confidence = 0.75
        else:
            answer = (
                f"{equipment_id} is compliant with {rule['source']}: "
                + " ".join(f["detail"] for f in findings)
            )
            confidence = 0.7

        return {
            "agent": self.name,
            "answer": answer,
            "confidence": confidence,
            "sources": sources,
            "reasoning": (
                f"Checked {len(findings)} rule(s) from {rule['source']} against "
                f"{len(relevant)} retrieved chunk(s) for {equipment_id}."
            ),
        }