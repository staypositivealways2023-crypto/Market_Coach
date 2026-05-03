"""
ChromaDB Per-User Memory — Phase 11 + Phase 4 (Deep Memory System)

Stores and retrieves semantic memories for each user so the CoachAgent
can personalise its output across sessions.

Collections:
  user_memory_{uid}   — per-user memory chunks
    documents : natural-language memory snippets
    metadata  : { timestamp, category, symbol, uid }

Categories (original 5):
  preference    — user's stated risk tolerance, goals, style
  portfolio     — symbols watched / traded
  learning      — lesson completions, quiz scores
  conversation  — session summaries (saved after voice/chat sessions)
  event         — notable trading events (paper trade opened, analysis run)

Categories (Phase 4 additions):
  trade_history      — symbols analysed + crew output summaries
  risk_profile       — position sizing habits, stop-loss adherence patterns
  watchlist_patterns — symbols repeatedly returned to / watched closely
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

    def recall_with_metadata(
        self,
        uid: str,
        query: str,
        n: int = 10,
        category: Optional[str] = None,
    ) -> list[dict]:
        """
        Semantic search — returns n most relevant entries as dicts:
          { id, text, category, timestamp, symbol, distance }
        Falls back to [] if chromadb is unavailable.
        """
        col = self._collection(uid)
        if col is None:
            return []

        try:
            where = {"uid": uid}
            if category:
                where["category"] = category  # type: ignore[assignment]

            count = col.count()
            if count == 0:
                return []

            results = col.query(
                query_texts=[query],
                n_results=min(n, count),
                where=where if len(where) > 1 else None,
                include=["documents", "metadatas", "distances"],
            )
            ids       = results.get("ids",       [[]])[0]
            docs      = results.get("documents", [[]])[0]
            metas     = results.get("metadatas", [[]])[0]
            distances = results.get("distances", [[]])[0]

            entries = []
            for doc_id, doc, meta, dist in zip(ids, docs, metas, distances):
                if not doc:
                    continue
                m = meta or {}
                entries.append({
                    "id":        doc_id,
                    "text":      doc,
                    "category":  m.get("category", "event"),
                    "timestamp": int(m.get("timestamp", 0)),
                    "symbol":    m.get("symbol"),
                    "distance":  round(float(dist), 4),
                })
            return entries
        except Exception as e:
            logger.error(f"[chroma] recall_with_metadata error for {uid}: {e}")
            return []

    def delete_entry(self, uid: str, doc_id: str) -> bool:
        """
        Delete a single memory entry by its ChromaDB document ID.
        Returns True on success.
        """
        col = self._collection(uid)
        if col is None:
            return False
        try:
            col.delete(ids=[doc_id])
            logger.info(f"[chroma] deleted entry {doc_id} for {uid}")
            return True
        except Exception as e:
            logger.error(f"[chroma] delete_entry error for {uid}: {e}")
            return False

    def get_timeline(
        self,
        uid: str,
        limit: int = 100,
        category: Optional[str] = None,
    ) -> list[dict]:
        """
        Return all (or category-filtered) memory entries sorted by timestamp
        descending. Used by the Flutter memory timeline screen.

        Returns list of dicts:
          { id, text, category, timestamp, symbol }
        """
        col = self._collection(uid)
        if col is None:
            return []

        try:
            count = col.count()
            if count == 0:
                return []

            where = {"uid": uid}
            if category:
                where["category"] = category  # type: ignore[assignment]

            results = col.get(
                limit=min(limit, count),
                where=where if len(where) > 1 else None,
                include=["documents", "metadatas"],
            )
            ids   = results.get("ids",       [])
            docs  = results.get("documents", [])
            metas = results.get("metadatas", [])

            entries = []
            for doc_id, doc, meta in zip(ids, docs, metas):
                if not doc:
                    continue
                m = meta or {}
                entries.append({
                    "id":        doc_id,
                    "text":      doc,
                    "category":  m.get("category", "event"),
                    "timestamp": int(m.get("timestamp", 0)),
                    "symbol":    m.get("symbol"),
                })

            # Sort newest-first in Python (ChromaDB has no server-side ORDER BY)
            entries.sort(key=lambda x: x["timestamp"], reverse=True)
            return entries
        except Exception as e:
            logger.error(f"[chroma] get_timeline error for {uid}: {e}")
            return []

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
