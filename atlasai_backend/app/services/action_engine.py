"""
Day 6: AI Action Engine.

Generates structured operational documents (RCA report, maintenance
checklist, inspection schedule, audit report) grounded in whatever's
actually been ingested for the equipment in question — same retrieval
approach as knowledge_agent.py (broad semantic retrieval, no ChromaDB
where-clause dependency), then a template-specific system prompt tells
Groq what structure/sections to produce.

Deliberately reuses retrieval rather than introducing a new pipeline:
the whole point of the Action Engine per the plan is "generate an
action from the same context" the Knowledge Agent already grounded its
answer in — not a separate, disconnected feature.
"""
from typing import Any, Dict, List, Optional

from app.services import embeddings, groq_client
from app.services.chroma_client import get_documents_collection
from app.services import graph_service

ACTION_TYPES = {
    "rca_report": {
        "title": "Root Cause Analysis Report",
        "instructions": (
            "Produce a structured Root Cause Analysis report using these exact section titles "
            "in Markdown bold (do NOT use Markdown headings like #, ##, ###): "
            "**Incident Summary**, **Timeline**, **Suspected Root Cause**, "
            "**Contributing Factors**, **Corrective Actions Taken**, "
            "**Preventive Recommendations**. "
            "Place each bold section title on its own line, followed by its content on the next line(s). "
            "Base every claim strictly on the provided context. If a section has no supporting "
            "evidence, write 'Not documented in available records'."
        ),
    },

    "maintenance_checklist": {
        "title": "Maintenance Checklist",
        "instructions": (
            "Produce a maintenance checklist grounded in the provided context. "
            "Group items under Markdown bold section titles (NOT Markdown headings), using this layout:\n\n"
            "**Mechanical**\n1. ...\n2. ...\n\n"
            "**Lubrication**\n1. ...\n\n"
            "**Electrical**\n1. ...\n\n"
            "**General**\n1. ...\n\n"
            "Only include categories supported by the context. "
            "Keep each checklist item short, concrete, and field-usable."
        ),
    },

    "inspection_schedule": {
        "title": "Inspection Schedule",
        "instructions": (
            "Produce an inspection schedule using Markdown bold section titles (NOT Markdown headings). "
            "For each inspection item, use this format:\n\n"
            "**Inspection Item**\n"
            "**Frequency**\n"
            "**Last Recorded**\n"
            "**Next Due**\n\n"
            "If the last inspection date is unavailable, write 'Unknown'. "
            "If the next due date cannot be calculated, write "
            "'Cannot calculate — last date unknown'. "
            "Do not invent inspection frequencies."
        ),
    },

    "preventive_maintenance": {
        "title": "Preventive Maintenance Plan",
        "instructions": (
            "Produce a preventive maintenance plan using Markdown bold section titles "
            "(NOT Markdown headings): "
            "**Preventive Tasks**, **Recommended Frequency**, **Rationale**. "
            "**Preventive Tasks** should contain a numbered list of field-usable actions. "
            "Use only frequencies supported by the context; otherwise write "
            "'No frequency documented — recommend establishing one'. "
            "Base every rationale strictly on the provided context."
        ),
    },

    "audit_report": {
        "title": "Audit Report",
        "instructions": (
            "Produce an audit report using Markdown bold section titles "
            "(NOT Markdown headings): "
            "**Scope**, **Records Reviewed**, **Findings**, "
            "**Compliance Status**, **Recommendations**. "
            "Under **Records Reviewed**, list each source filename on a separate line. "
            "Under **Findings**, clearly distinguish confirmed facts from missing information."
        ),
    },
}


def _normalize_role(user_role: str) -> Optional[str]:
    """Maps the incoming user_role string to one of the two role-aware
    profiles this module knows how to write for. The Flutter app
    currently sends 'manager' (see ManagerHome/ActionResultScreen)
    rather than 'plant_manager' — both are treated as the same
    plant-manager profile so the feature actually engages for the
    existing call sites without requiring any Flutter change. Any
    other role (e.g. 'technician', 'auditor') falls back to the
    original neutral, role-agnostic instructions."""
    role = (user_role or "").strip().lower()
    if role in {"engineer", "maintenance_engineer"}:
        return "engineer"
    if role in {"plant_manager", "manager"}:
        return "plant_manager"
    return None


# Role-aware guidance appended on top of each action type's base
# instructions. This only changes presentation, recommended next
# steps, and level of detail — never the underlying facts, which stay
# strictly grounded in the retrieved context regardless of role (see
# the "Use ONLY the provided context" line kept in system_prompt
# below, unchanged for every role).
ROLE_GUIDANCE = {
    "engineer": {
        "rca_report": (
            "Write this for a maintenance engineer who will act on it directly. Under "
            "'Corrective Actions Taken:' and 'Preventive Recommendations:', be concrete and "
            "execution-focused — specific components, tools, measurements, and verification "
            "steps a technician can carry out, not high-level planning language."
        ),
        "maintenance_checklist": (
            "Write this as a field-ready checklist for a maintenance engineer performing the "
            "work. Under each category, include concrete, hands-on steps covering: inspection, "
            "testing, lubrication (with points/intervals if the context supports them), "
            "measurements to take, repair steps, replacement of worn components, safety "
            "precautions to observe while performing the work, and a verification step to "
            "confirm the equipment is operating correctly after maintenance is complete. "
            "Every single item must describe a physical action the engineer performs with "
            "their hands or tools right now (e.g. 'Inspect the coupling for misalignment', "
            "'Lubricate the drive-end bearing', 'Measure vibration at the pump housing', "
            "'Replace the worn seal'). This checklist is for the person doing the work, not "
            "for someone tracking it."
        ),
        "inspection_schedule": (
            "Write this for a maintenance engineer who will perform the inspections. For each "
            "item, make 'Inspection Item:' specific enough to act on directly (what to check "
            "and how — e.g. a measurement, a visual check, a test), not just a category name."
        ),
        "audit_report": (
            "Write 'Findings:' and 'Recommendations:' with the technical detail a maintenance "
            "engineer needs to close out any gaps directly — specific components, checks, or "
            "corrective technical work implied by the findings."
        ),
        "preventive_maintenance": (
            "Write 'Preventive Tasks:' as concrete, hands-on field actions a maintenance "
            "engineer can perform directly, with enough detail (what to check, replace, or "
            "measure) to execute without needing to ask follow-up questions."
        ),
    },
    "plant_manager": {
        "rca_report": (
            "Write this for a plant manager reviewing the incident for operational "
            "decision-making. Under 'Preventive Recommendations:', frame actions in terms of "
            "scheduling, ownership/assignment, monitoring cadence, and whether this fits a "
            "recurring incident pattern worth escalating — not step-by-step repair "
            "instructions."
        ),
        "maintenance_checklist": (
            "Write this for a plant manager, not the technician performing the work. Reframe "
            "each category around planning and tracking rather than hands-on steps: whether a "
            "work order exists and is assigned, whether required spare parts are available, "
            "whether manpower is allocated, the scheduled/preventive maintenance interval, and "
            "a verification item confirming the checklist was completed and signed off. Do not "
            "include detailed hands-on repair steps — only mention verification that the work "
            "was completed."
        ),
        "inspection_schedule": (
            "Write this for a plant manager. For each item, frame 'Frequency:' and 'Next Due:' "
            "around scheduling and compliance tracking (e.g. flag if an inspection is overdue, "
            "and what resourcing/planning is needed to complete it), rather than describing how "
            "to physically perform the inspection."
        ),
        "audit_report": (
            "Write 'Findings:', 'Compliance Status:', and 'Recommendations:' for a plant "
            "manager: emphasize compliance status, risk assessment, recurring-incident "
            "analysis, and work-order/process-level recommendations for operational "
            "decision-making. Do not include detailed hands-on repair steps — only mention "
            "verification that corrective actions have been completed."
        ),
        "preventive_maintenance": (
            "Write this for a plant manager. Frame 'Preventive Tasks:' around scheduling, "
            "ownership, and tracking (what needs to be planned and by when), and use "
            "'Rationale:' to tie tasks back to recurring incident trends, compliance, or "
            "downtime/risk reduction — not hands-on execution detail."
        ),
    },
}


async def _retrieve_context(query: str, equipment_id: Optional[str], n_results: int = 8) -> List[Dict[str, Any]]:
    """Same broad-retrieve-then-filter pattern as maintenance_agent.py —
    no ChromaDB where-clause, since that's proven unreliable in this
    environment's ChromaDB version across several rounds of testing."""
    collection = get_documents_collection()
    if collection.count() == 0:
        return []

    query_vec = await embeddings.embed(query)
    n = min(n_results, collection.count())
    results = collection.query(query_embeddings=[query_vec], n_results=n)

    docs = results.get("documents", [[]])[0]
    metas = results.get("metadatas", [[]])[0]

    chunks = [{"text": d, "meta": m} for d, m in zip(docs, metas)]
    if equipment_id:
        scoped = [c for c in chunks if c["meta"].get("equipment_id") == equipment_id]
        if scoped:
            return scoped
    return chunks


async def generate_action(
    action_type: str,
    query: str,
    equipment_id: Optional[str] = None,
    user_role: str = "technician",
) -> Dict[str, Any]:
    if action_type not in ACTION_TYPES:
        raise ValueError(f"Unknown action_type '{action_type}'. Valid: {sorted(ACTION_TYPES)}")

    spec = ACTION_TYPES[action_type]
    search_query = query or f"{spec['title']} for {equipment_id or 'this equipment'}"
    chunks = await _retrieve_context(search_query, equipment_id)

    if not chunks:
        return {
            "actionType": action_type,
            "title": spec["title"],
            "content": (
                f"No documents have been ingested yet for "
                f"{equipment_id or 'this equipment'} — nothing to ground a "
                f"{spec['title'].lower()} in. Ingest a maintenance log, incident "
                f"report, or SOP first."
            ),
            "sources": [],
            "confidence": 0.0,
        }

    context_lines = []
    sources = []
    for i, chunk in enumerate(chunks[:6], start=1):
        context_lines.append(f"[{i}] {chunk['text']}")
        fname = chunk["meta"].get("file_name", "unknown")
        sources.append(fname)
    context_block = "\n\n".join(context_lines)

    graph_note = ""
    if equipment_id:
        try:
            graph_note = graph_service.graph_context_summary(equipment_id.upper())
        except Exception:
            graph_note = ""

    role_key = _normalize_role(user_role)
    role_guidance = ROLE_GUIDANCE.get(role_key, {}).get(action_type, "") if role_key else ""

    system_prompt = (
    "You are the AI Action Engine for AtlasAI, an industrial knowledge assistant. "
    f"{spec['instructions']} "
    + (f"{role_guidance} " if role_guidance else "")
    + "Use ONLY the provided context — do not invent equipment history, dates, or names "
    "that aren't in it. Cite sources inline using [1], [2] etc matching the context "
    f"numbers given. Write for a {user_role}: adjust technical depth accordingly, but "
    "keep every factual claim traceable to the context. Role only changes presentation, "
    "recommended next steps, and level of detail — never the underlying facts, which "
    "must stay identical regardless of who's reading. "
    "Formatting rules for your output, without exception: return plain text only. "
    "Do not use Markdown headings (#, ##, ###, ####). "
    "Do not use Markdown tables. "
    "Use Markdown bold (**) only for section titles. "
    "For example: **Incident Summary**, **Timeline**, **Preventive Recommendations**, "
    "**Mechanical**, **Electrical**, **General**. "
    "Do not bold normal paragraphs, checklist items, numbered lists, or bullet points. "
    "Keep one blank line between sections so the output stays readable and mobile-friendly."
    )
    user_prompt = (
        f"Equipment: {equipment_id or 'not specified'}\n"
        f"{'Knowledge Graph: ' + graph_note if graph_note else ''}\n\n"
        f"Context:\n{context_block}\n\n"
        f"Generate the {spec['title']}."
    )

    try:
        content = await groq_client.chat_completion(system_prompt, user_prompt)
        confidence = min(1.0, 0.5 + 0.05 * len(chunks[:6]))
    except Exception as e:
        content = (
            f"Groq generation unavailable ({e}). Raw retrieved context follows instead:\n\n"
            + context_block
        )
        confidence = 0.2

    return {
        "actionType": action_type,
        "title": spec["title"],
        "content": content,
        "sources": sorted(set(sources)),
        "confidence": round(confidence, 2),
    }