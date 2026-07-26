"""
Day 4 — Entity Extraction

Extends Day 2's equipment-tag-only extraction with dates and personnel
names, plus a lightweight document-type classifier. This is what the
Knowledge Graph (graph_service.py) uses to build real
equipment <-> SOP <-> incident <-> technician <-> maintenance-record
edges instead of just equipment -> document.

Kept dependency-free (regex/heuristics) on purpose — no spaCy/NLP model
to download or fail mid-demo. Good enough for structured industrial
docs (SOPs, incident reports, maintenance logs); not meant to be a
general-purpose NER system.
"""
import re
from typing import Any, Dict, List

# Reuse the same tag pattern ingestion.py already uses, so equipment_tags
# stay identical between the two modules.
EQUIPMENT_PATTERN = re.compile(
    r"\b(PUMP|VALVE|COMPRESSOR|TANK|MOTOR|BOILER|TURBINE|CONVEYOR)[\s-]?(\d{1,3})\b",
    re.IGNORECASE,
)

DATE_PATTERN = re.compile(
    r"\b("
    r"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"  # 12/04/2026, 12-4-26
    r"|\d{4}-\d{2}-\d{2}"  # 2026-04-12 (ISO)
    r"|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}"  # April 12, 2026
    r")\b",
    re.IGNORECASE,
)

# Personnel: look for a name directly after a role/label cue, since bare
# "Capitalized Word" matching drowns in false positives on industrial
# docs full of proper-noun-looking equipment/location names.
PERSONNEL_CUE_PATTERN = re.compile(
    r"(?:Inspected by|Reported by|Prepared by|Reviewed by|Approved by|"
    r"Technician|Engineer|Supervisor|Attended by)\s*[:\-]?\s*"
    r"([A-Z][a-zA-Z.]+(?:\s+[A-Z][a-zA-Z.]+){0,2})"
)

DOC_TYPE_KEYWORDS = {
    "sop": ["standard operating procedure", "sop", "step-by-step procedure"],
    "incident": ["incident report", "near miss", "near-miss", "accident report"],
    "maintenance_record": [
        "maintenance log", "maintenance record", "work order",
        "service report", "repair log",
    ],
    "manual": ["oem manual", "operation manual", "user manual", "instruction manual"],
    "compliance": ["audit report", "inspection checklist", "compliance report", "oisd"],
}


def extract_equipment_tags(full_text: str) -> List[str]:
    tags = set()
    for match in EQUIPMENT_PATTERN.finditer(full_text):
        kind, num = match.groups()
        tags.add(f"{kind.upper()}-{int(num):02d}")
    return sorted(tags)


def extract_dates(full_text: str) -> List[str]:
    return sorted(set(m.group(0) for m in DATE_PATTERN.finditer(full_text)))


def extract_personnel(full_text: str) -> List[str]:
    names = set()
    for m in PERSONNEL_CUE_PATTERN.finditer(full_text):
        candidate = m.group(1).strip()
        # Guard against picking up equipment tags or generic words that
        # happen to be capitalized right after a cue phrase.
        if EQUIPMENT_PATTERN.search(candidate):
            continue
        names.add(candidate)
    return sorted(names)


def classify_document_type(full_text: str) -> str:
    lowered = full_text.lower()
    for doc_type, keywords in DOC_TYPE_KEYWORDS.items():
        if any(kw in lowered for kw in keywords):
            return doc_type
    return "general_document"


def extract_entities(full_text: str) -> Dict[str, Any]:
    """Single entry point ingestion.py / main.py calls — everything
    Day 4's Knowledge Graph needs to link a document into the graph."""
    return {
        "equipment_tags": extract_equipment_tags(full_text),
        "dates": extract_dates(full_text),
        "personnel": extract_personnel(full_text),
        "doc_type": classify_document_type(full_text),
    }