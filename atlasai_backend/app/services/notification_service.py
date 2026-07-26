"""
Day 5: push notifications for Lessons Learned matches.

Same fail-safe pattern as Day 4's graph_service Firestore sync: opt-in
via env vars, never raises, no-ops cleanly if unconfigured. /ingest must
never fail because a notification couldn't be sent.
"""
import os

_initialized = False


def _ensure_app() -> bool:
    global _initialized
    if _initialized:
        return True

    cred_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
    if not cred_path or not os.path.exists(cred_path):
        return False

    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
        _initialized = True
        return True
    except Exception:
        return False


def is_enabled() -> bool:
    return os.getenv("ENABLE_FCM_ALERTS", "false").lower() == "true"


def send_lessons_learned_alert(
    equipment_id: str,
    doc_id: str,
    file_name: str,
    match_count: int,
) -> bool:
    """Best-effort push to the 'lessons_learned' topic. Flutter clients
    subscribe to this topic on launch (see fcm_service.dart) — anyone
    with the app installed gets the alert, not just the uploader."""
    if not is_enabled() or not _ensure_app():
        return False

    try:
        from firebase_admin import messaging

        label = equipment_id or file_name
        message = messaging.Message(
            notification=messaging.Notification(
                title="AtlasAI — Similar incident detected",
                body=(
                    f"New report on {label} matches {match_count} past "
                    f"incident(s). Review before it recurs."
                ),
            ),
            data={
                "type": "lessons_learned",
                "docId": doc_id,
                "equipmentId": equipment_id or "",
            },
            topic="lessons_learned",
        )
        messaging.send(message)
        return True
    except Exception:
        return False