import re
import time
import uuid
from typing import List, Dict, Any

import fitz  # PyMuPDF
import pytesseract
from PIL import Image
import io

from app.telemetry import tracer
from app.otel_metrics import ocr_page_duration_ms, ocr_pages_total, ocr_failures_total


def extract_pages(file_bytes: bytes) -> List[str]:
    with tracer.start_as_current_span("ingestion.extract_pages") as doc_span:
        doc = fitz.open(stream=file_bytes, filetype="pdf")
        pages_text = []
        for page_num, page in enumerate(doc, start=1):
            page_start = time.perf_counter()
            method = "text_layer"
            with tracer.start_as_current_span(
                "ingestion.extract_page", attributes={"atlasai.ocr.page": page_num}
            ) as page_span:
                text = page.get_text("text").strip()
                if len(text) < 20:
                    method = "ocr_fallback"
                    try:
                        pix = page.get_pixmap(dpi=200)
                        img = Image.open(io.BytesIO(pix.tobytes("png")))
                        text = pytesseract.image_to_string(img).strip()
                        if not text:
                            ocr_failures_total.add(1, {"reason": "empty_result"})
                    except Exception as e:
                        ocr_failures_total.add(1, {"reason": type(e).__name__})
                        page_span.record_exception(e)
                        text = ""

                page_span.set_attribute("atlasai.ocr.method", method)
                ocr_page_duration_ms.record(
                    (time.perf_counter() - page_start) * 1000, {"method": method}
                )
                ocr_pages_total.add(1, {"method": method})

            pages_text.append(text)
        doc.close()
        doc_span.set_attribute("atlasai.ocr.total_pages", len(pages_text))
        return pages_text


def chunk_text(text: str, chunk_size: int = 800, overlap: int = 150) -> List[str]:
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return []
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + chunk_size, len(text))
        chunks.append(text[start:end])
        if end == len(text):
            break
        start = end - overlap
    return chunks


EQUIPMENT_PATTERN = re.compile(
    r"\b(PUMP|VALVE|COMPRESSOR|TANK|MOTOR|BOILER|TURBINE|CONVEYOR)[\s-]?(\d{1,3})\b",
    re.IGNORECASE,
)


def extract_equipment_tags(full_text: str) -> List[str]:
    tags = set()
    for match in EQUIPMENT_PATTERN.finditer(full_text):
        kind, num = match.groups()
        tag = f"{kind.upper()}-{int(num):02d}"
        tags.add(tag)
    return sorted(tags)


def build_graph_edges(doc_id: str, equipment_tags: List[str]) -> List[Dict[str, Any]]:
    edges = []
    for tag in equipment_tags:
        edges.append({
            "edgeId": str(uuid.uuid4()),
            "fromType": "equipment",
            "fromId": tag,
            "toType": "document",
            "toId": doc_id,
            "relation": "documented_by",
        })
    return edges


# =========================================================================
# Day 4: dates + personnel extraction
# =========================================================================

_MONTHS = (
    r"Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|"
    r"Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?"
)

DATE_PATTERNS = [
    re.compile(r"\b\d{4}-\d{2}-\d{2}\b"),                                       # 2026-07-14
    re.compile(r"\b\d{1,2}/\d{1,2}/\d{2,4}\b"),                                 # 14/07/2026
    re.compile(rf"\b(?:{_MONTHS})\s+\d{{1,2}},?\s+\d{{4}}\b", re.IGNORECASE),   # July 14, 2026
    re.compile(rf"\b\d{{1,2}}\s+(?:{_MONTHS}),?\s+\d{{4}}\b", re.IGNORECASE),   # 14 July 2026
]


def extract_dates(full_text: str) -> List[str]:
    found = set()
    for pattern in DATE_PATTERNS:
        for match in pattern.finditer(full_text):
            found.add(match.group().strip())
    return sorted(found)


# Personnel — regex-based, not full NER (deliberate hackathon-scope choice,
# avoids adding spaCy + a language model on top of the torch/
# sentence-transformers image already in this build).
#
# IMPORTANT: (?i:...) scopes case-insensitivity to ONLY the role-keyword
# alternation below — there is deliberately no global re.IGNORECASE flag
# on these patterns. Applying IGNORECASE globally makes [A-Z] match
# lowercase too, defeating the "must be a capitalized name" check —
# verified this directly: an earlier version silently swallowed trailing
# lowercase words ("Rakesh Sharma" -> "Rakesh Sharma.\nWhat do") because
# nothing stopped the name group from matching ordinary lowercase words
# after the real name ended.
ROLE_KEYWORDS_LIST = [
    "Technician", "Engineer", "Inspector", "Supervisor", "Operator",
    "Shift Engineer", "Reported by", "Inspected by", "Signed by",
    "Prepared by", "Reviewed by", "Approved by", "Checked by", "Attended by",
]
ROLE_KEYWORDS = "|".join(kw.replace(" ", r"\s+") for kw in ROLE_KEYWORDS_LIST)

# Exactly 2-3 capitalized words or a single-letter initial ("A.") per
# token — this is what enforces "looks like a proper name" and stops
# the match from bleeding into the next sentence.
NAME_TOKEN = r"[A-Z][a-z]+|[A-Z]\."
HONORIFIC_PREFIX = r"(?:(?:Mr|Ms|Mrs|Dr)\.\s+)?"
NAME_CORE = rf"(?:{NAME_TOKEN})(?:\s+(?:{NAME_TOKEN})){{0,2}}"
NAME_PATTERN = rf"{HONORIFIC_PREFIX}{NAME_CORE}"

ROLE_LABELED_PATTERN = re.compile(rf"\b((?i:{ROLE_KEYWORDS}))\s*[:\-]\s*({NAME_PATTERN})")
HONORIFIC_PATTERN = re.compile(rf"\b(?:Mr|Ms|Mrs|Dr)\.\s+({NAME_CORE})\b")

_HONORIFIC_STRIP = re.compile(r"^(?:Mr|Ms|Mrs|Dr)\.\s+")


def extract_personnel(full_text: str) -> List[Dict[str, str]]:
    """Returns deduplicated [{"name": ..., "role": ...}, ...], sorted by
    name. role is the labeling keyword normalized to snake_case
    (e.g. "inspected_by"), or "mentioned" for honorific-only matches.
    Honorific prefixes (Dr./Mr./Ms./Mrs.) are stripped from the stored
    name so "Dr. Anita Rao" (role-labeled) and "Anita Rao" (bare
    honorific mention elsewhere in the doc) collapse to one person."""
    people: Dict[str, str] = {}

    for role_raw, name_raw in ROLE_LABELED_PATTERN.findall(full_text):
        name = _HONORIFIC_STRIP.sub("", name_raw.strip())
        role = re.sub(r"\s+", "_", role_raw.strip().lower())
        if name not in people:
            people[name] = role

    for name_raw in HONORIFIC_PATTERN.findall(full_text):
        name = name_raw.strip()
        if name not in people:
            people[name] = "mentioned"

    return [{"name": n, "role": r} for n, r in sorted(people.items())]


def extract_entities(full_text: str) -> Dict[str, Any]:
    """Document-level entity summary — the Day 4 deliverable."""
    return {
        "equipment": extract_equipment_tags(full_text),
        "dates": extract_dates(full_text),
        "personnel": extract_personnel(full_text),
    }