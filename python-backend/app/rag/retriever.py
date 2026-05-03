"""
RAG retriever — lazy-loaded VectorStoreIndex backed by pgvector.

Public API:
    from app.rag.retriever import rag_search

    # Returns top-k relevant document chunks as a single string.
    context = await rag_search("Apple revenue growth 2024", top_k=5)

Design notes:
- _index is a module-level singleton, loaded on first call.
- Subsequent calls skip the load and go straight to retrieval.
- After API restart, VectorStoreIndex.from_vector_store() reads the
  existing pgvector table — no re-ingestion needed.
- Retrieval is synchronous under the hood (psycopg2); we run it in
  asyncio's default ThreadPoolExecutor to avoid blocking the event loop.
- Returns "" on any error so tool_router degrades gracefully.
"""

import asyncio
import logging
from typing import Optional

from llama_index.core import StorageContext, VectorStoreIndex

from app.rag.embedder import get_embedder
from app.rag.ingestor import build_vector_store

logger = logging.getLogger(__name__)

# ── Module-level singleton ────────────────────────────────────────────────────
_index: Optional[VectorStoreIndex] = None


def _load_index() -> Optional[VectorStoreIndex]:
    """
    Load (or return cached) the VectorStoreIndex from pgvector.

    Thread-safe for read access — LangGraph nodes run in async context
    but the ThreadPoolExecutor serialises first-load.
    """
    global _index
    if _index is not None:
        return _index

    try:
        vector_store = build_vector_store()
        _index = VectorStoreIndex.from_vector_store(
            vector_store,
            embed_model=get_embedder(),
        )
        logger.info("[retriever] Index loaded from pgvector (persistent store).")
        return _index
    except Exception as exc:
        logger.error("[retriever] Failed to load index from pgvector: %s", exc)
        return None


def reset_index() -> None:
    """
    Force the singleton to reload on next call.
    Used in tests to simulate API restart without re-ingestion.
    """
    global _index
    _index = None
    logger.debug("[retriever] Index reset — will reload on next rag_search call.")


# ── Synchronous retrieval (runs in executor) ──────────────────────────────────

def _sync_search(query: str, top_k: int) -> str:
    """
    Retrieve the top-k most relevant document chunks for query.
    Runs synchronously; called via run_in_executor from async context.
    """
    index = _load_index()
    if index is None:
        logger.warning("[retriever] Index unavailable — returning empty context.")
        return ""

    retriever = index.as_retriever(similarity_top_k=top_k)
    nodes = retriever.retrieve(query)

    if not nodes:
        logger.info("[retriever] No nodes found for query: '%s'", query[:60])
        return ""

    chunks = [n.get_content() for n in nodes]
    result = "\n\n---\n\n".join(chunks)

    logger.info(
        "[retriever] rag_search('%s...') → %d chunks, %d chars",
        query[:40],
        len(nodes),
        len(result),
    )
    return result


# ── Public async API ──────────────────────────────────────────────────────────

async def rag_search(query: str, top_k: int = 5) -> str:
    """
    Async RAG retrieval over the pgvector financial document store.

    Args:
        query:  Natural-language query (e.g. "Apple revenue growth 2024").
        top_k:  Number of document chunks to retrieve (default 5).

    Returns:
        Relevant document text as a single string, or "" on failure.
    """
    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(None, _sync_search, query, top_k)
        return result
    except Exception as exc:
        logger.error("[retriever] rag_search error for query '%s': %s", query[:60], exc)
        return ""
