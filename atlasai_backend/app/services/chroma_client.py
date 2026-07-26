import os
import chromadb

_client = None
_documents_collection = None


def get_client():
    global _client

    if _client is None:
        db_path = os.getenv("CHROMA_DB_PATH", "./chroma_db")

        _client = chromadb.PersistentClient(
            path=db_path
        )

    return _client


def get_documents_collection():
    global _documents_collection

    if _documents_collection is None:
        _documents_collection = get_client().get_or_create_collection(
            name="documents"
        )

    return _documents_collection