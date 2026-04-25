"""
ChromaDB Per-User Memory — Phase 11

Stores and retrieves semantic memories for each user so the CoachAgent
can personalise its output across sessions.

Collections:
  user_memory_{uid}   — per-user memory chunks
    documents : natural-language memory snippets
    metadata  : { timestamp, category, symbol }

Categories:
  preference    — user's stated risk tolerance, goals, style
  portfolio     — symbols watched / traded
  learning      — lesson completions, quiz scores
  conversation  — session summaries (saved after voice/chat sessions)
  event         — notable trading events (paper trade opened, analysis run)
"""

import logging
import os
import time
from typing import Optional

logger = logging.getLogger(__name__)

# Lazily initialise ChromaDB so the app starts even if chromadb isn't installed
_chroma_client = None


def _get_client():
    global _chroma_client
    if _chroma_client is not None:
        return _chroma_client
    try:
        import chromadb
        persist_path = os.getenv("CHROMA_PERSIST_PATH", "./chroma_data")
        _chroma_client = chromadb.PersistentClient(path=persist_path)
        logger.info(f"[chroma] initialised at {persist_path}")
    except ImportError:
        logger.warning("[chroma] chromadb not installed — memory disabled")
        _chroma_client = None
    except Exception as e:
        logger.error(f"[chroma] init failed: {e}")
        _chroma_client = None
    return _chroma_client


class ChromaMemoryService:
    """
    Thin wrapper around a ChromaDB persistent client.
    Gracefully no-ops if chromadb is not installed.
    """

    def _collection(self, uid: str):
        """Get or create the per-user collection."""
        client = _get_client()
        if client is None:
            return None
        name = f"user_memory_{uid.replace('-', '_').replace('.', '_')[:40]}"
        try:
            return client.get_or_create_collection(
                name=name,
                metadata={"hnsw:space": "cosine"},
            )
        except Exception as e:
            logger.error(f"[chroma] collection error for {uid}: {e}")
            return None

    def store(
        self,
        uid: str,
        text: str,
        category: str = "event",
        symbol: Optional[str] = None,
    ) -> bool:
        """
        Store a memory snippet for a user.
        Returns True on success, False if chromadb is unavailable.
        """
        col = self._collection(uid)
        if col is None:
            return False

        doc_id = f"{uid}_{int(time.time() * 1000)}"
        metadata = {
            "timestamp": int(time.time()),
            "category":  category,
            "uid":       uid,
        }
        if symbol:
            metadata["symbol"] = symbol

        try:
            col.add(
                documents=[text],
                metadatas=[metadata],
                ids=[doc_id],
            )
            logger.debug(f"[chroma] stored memory for {uid}: {text[:80]}")
            return True
        except Exception as e:
            logger.error(f"[chroma] store error for {uid}: {e}")
            return False

    def recall(
        self,
        uid: str,
        query: str,
        n: int = 5,
        category: Optional[str] = None,
    ) -> list[str]:
        """
        Semantic search — returns the n most relevant memory snippets.
        Falls back to [] if chromadb is unavailable.
        """
        col = self._collection(uid)
        if col is None:
            return []

        try:
            where = {"uid": uid}
            if category:
                where["category"] = category   # type: ignore[assignment]

            count = col.count()
            if count == 0:
                return []

            results = col.query(
                query_texts=[query],
                n_results=min(n, count),
                where=where if len(where) > 1 else None,
            )
            docs = results.get("documents", [[]])[0]
            return [d for d in docs if d]
        except Exception as e:
            logger.error(f"[chroma] recall error for {uid}: {e}")
            return []

    def summarise_user(self, uid: str) -> str:
        """
        Returns a plain-English summary of what we know about the user.
        Used in the Coach agent's system prompt.
        """
        col = self._collection(uid)
        if col is None:
            return "No memory available for this user."

        try:
            count = col.count()
            if count == 0:
                return "This is a new user — no prior history available."

            # Sample up to 20 recent memories across categories
            results = col.get(limit=20, include=["documents", "metadatas"])
            docs   = results.get("documents", [])
            metas  = results.get("metadatas", [])

            lines = [f"User profile (based on {count} stored memories):"]
            for doc, meta in zip(docs, metas):
                cat = meta.get("category", "event") if meta else "event"
                lines.append(f"[{cat}] {doc}")

            return "\n".join(lines[:15])  # cap length
        except Exception as e:
            logger.error(f"[chroma] summarise error for {uid}: {e}")
            return "Memory summary unavailable."

    def delete_user(self, uid: str) -> bool:
        """GDPR: delete all memories for a user."""
        client = _get_client()
        if client is None:
            return False
        name = f"user_memory_{uid.replace('-', '_').replace('.', '_')[:40]}"
        try:
            client.delete_collection(name)
            logger.info(f"[chroma] deleted collection for {uid}")
            return True
        except Exception as e:
            logger.error(f"[chroma] delete error for {uid}: {e}")
            return False
