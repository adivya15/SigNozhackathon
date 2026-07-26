"""
Day 4 — Firebase Admin client.

The backend needs write access to Firestore for the first time (the
`graph_edges` collection, per SCHEMA.md, is "Populated: Day 4"). Day 1-3
only ever wrote to ChromaDB.

Safety-net behaviour on purpose: Day 4 is called out in the plan as the
"safety-net milestone" — the demo has to work end-to-end even if Firebase
Admin credentials aren't configured on whichever machine you're running
on. So if init fails, we fall back to an in-memory store instead of
raising — ingestion/query keeps working, graph data just doesn't persist
across restarts until real credentials are added.
"""
import os
from typing import Any, Dict, List, Optional

_firestore_db = None
_init_attempted = False
_in_memory_store: Dict[str, Dict[str, Any]] = {}


def _try_init():
    global _firestore_db, _init_attempted
    if _init_attempted:
        return
    _init_attempted = True
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore

        cred_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
        if cred_path and os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
        else:
            # Works if GOOGLE_APPLICATION_CREDENTIALS is set in the
            # environment, or on GCP infra with default creds available.
            firebase_admin.initialize_app()
        _firestore_db = firestore.client()
        print("[firebase_admin_client] Connected to Firestore.", flush=True)
    except Exception as e:
        print(
            f"[firebase_admin_client] Firestore Admin unavailable ({e}). "
            "Falling back to in-memory graph store for this session — "
            "set FIREBASE_SERVICE_ACCOUNT_PATH in .env to persist for real.",
            flush=True,
        )
        _firestore_db = None


def is_connected() -> bool:
    _try_init()
    return _firestore_db is not None


def set_doc(collection: str, doc_id: str, data: Dict[str, Any]) -> None:
    _try_init()
    if _firestore_db is not None:
        _firestore_db.collection(collection).document(doc_id).set(data)
    else:
        _in_memory_store.setdefault(collection, {})[doc_id] = data


def get_collection(collection: str) -> List[Dict[str, Any]]:
    """Returns every doc in a collection as a list of dicts (each with
    its doc id folded in as `_id`). Fine at hackathon data volumes —
    not meant for production-scale collections."""
    _try_init()
    if _firestore_db is not None:
        docs = _firestore_db.collection(collection).stream()
        return [{**d.to_dict(), "_id": d.id} for d in docs]
    return [{**v, "_id": k} for k, v in _in_memory_store.get(collection, {}).items()]


def query_where_either(collection: str, field_a: str, field_b: str, value: str) -> List[Dict[str, Any]]:
    """Returns docs where field_a == value OR field_b == value.
    Used for graph traversal: 'edges touching this entity' means
    fromId == entity_id OR toId == entity_id."""
    all_docs = get_collection(collection)
    return [d for d in all_docs if d.get(field_a) == value or d.get(field_b) == value]