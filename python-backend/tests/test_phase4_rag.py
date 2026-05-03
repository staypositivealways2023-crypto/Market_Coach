"""
Phase 4 Exit Gate Tests — LlamaIndex + pgvector RAG
=====================================================

Run from the python-backend directory (inside Docker or with POSTGRES_HOST=localhost):

    pytest tests/test_phase4_rag.py -v

All tests are integration tests requiring:
  - postgres container healthy (market-coach-postgres)
  - ollama container healthy with nomic-embed-text pulled
  - Seed documents ingested at least once:
      python -m app.rag.ingestor

Tests skip automatically (not fail) when postgres is unreachable, so they
are safe to include in the standard CI suite — they only activate in the
full Docker environment.

Exit Gate Checklist (all 6 must pass):
  [1] Row count > 0 in pgvector after ingestion
  [2] rag_search("Apple revenue growth 2024") returns non-empty string with relevant content
  [3] RAG search completes in under 2 seconds
  [4] Re-running ingestor is idempotent (row count unchanged)
  [5] Index recovers from pgvector after reset (simulates API restart, no re-ingestion)
  [6] fundamental intent for AAPL includes rag_context in tool_results
"""

import asyncio
import time
import pytest
import psycopg2


# ── Helpers ──────────────────────────────────────────────────────────────────

def _postgres_available() -> bool:
    """Return True if the postgres container is reachable."""
    try:
        from app.config import settings
        conn = psycopg2.connect(
            host=settings.POSTGRES_HOST,
            port=int(settings.POSTGRES_PORT),
            dbname=settings.POSTGRES_DB,
            user=settings.POSTGRES_USER,
            password=str(settings.POSTGRES_PASSWORD),
            connect_timeout=3,
        )
        conn.close()
        return True
    except Exception:
        return False


def _ollama_available() -> bool:
    """Return True if the Ollama service is reachable."""
    try:
        import httpx
        r = httpx.get("http://ollama:11434/api/tags", timeout=3)
        return r.status_code == 200
    except Exception:
        try:
            import httpx
            # Fallback: check localhost (for running tests outside Docker)
            r = httpx.get("http://localhost:11434/api/tags", timeout=3)
            return r.status_code == 200
        except Exception:
            return False


requires_postgres = pytest.mark.skipif(
    not _postgres_available(),
    reason="postgres container not reachable — run inside Docker environment"
)

requires_ollama = pytest.mark.skipif(
    not _ollama_available(),
    reason="ollama container not reachable — run inside Docker environment"
)

requires_full_stack = pytest.mark.skipif(
    not (_postgres_available() and _ollama_available()),
    reason="full Docker stack (postgres + ollama) required"
)


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def ensure_ingested():
    """
    Ensure seed documents are ingested before running tests.
    Uses idempotent ingest (skips if already present).
    """
    from app.rag.ingestor import ingest_documents
    ingest_documents(force=False)


# ── Exit Gate 1: Row count > 0 after ingestion ───────────────────────────────

@requires_postgres
def test_exit_gate_1_row_count_after_ingestion(ensure_ingested):
    """
    GATE 1: psql query returns > 0 rows after ingestion.
    Verifies documents were actually written to the pgvector table.
    """
    from app.rag.ingestor import get_doc_count
    count = get_doc_count()
    assert count > 0, (
        f"Expected > 0 rows in pgvector after ingestion, got {count}. "
        "Run: python -m app.rag.ingestor"
    )
    print(f"\n  ✓ Gate 1: {count} document chunks in pgvector")


# ── Exit Gate 2: Relevant content returned ───────────────────────────────────

@requires_full_stack
def test_exit_gate_2_rag_search_returns_relevant_content(ensure_ingested):
    """
    GATE 2: rag_search('Apple revenue growth 2024') returns non-empty string
    containing relevant financial content.
    """
    from app.rag.retriever import rag_search

    result = asyncio.run(rag_search("Apple revenue growth 2024", top_k=3))

    assert result, "rag_search returned empty string — check ingestion and embedding"
    assert len(result) > 50, f"rag_search result too short: {len(result)} chars"

    # Verify relevant keywords are present in retrieved content
    result_lower = result.lower()
    relevant_terms = ["apple", "revenue", "billion"]
    matched = [term for term in relevant_terms if term in result_lower]
    assert len(matched) >= 2, (
        f"Retrieved content doesn't seem relevant. "
        f"Expected keywords {relevant_terms}, found: {matched}. "
        f"Content snippet: {result[:200]}"
    )
    print(f"\n  ✓ Gate 2: Retrieved {len(result)} chars — keywords found: {matched}")


# ── Exit Gate 3: Search completes under 2 seconds ────────────────────────────

@requires_full_stack
def test_exit_gate_3_rag_search_under_2_seconds(ensure_ingested):
    """
    GATE 3: RAG search (embed query + vector similarity) completes in < 2s.
    nomic-embed-text on GPU should embed a query in <100ms; pgvector ANN search in <50ms.
    """
    from app.rag.retriever import rag_search

    start = time.perf_counter()
    result = asyncio.run(rag_search("Tesla earnings gross margin Cybertruck", top_k=3))
    elapsed = time.perf_counter() - start

    assert elapsed < 2.0, (
        f"RAG search took {elapsed:.2f}s — exceeds 2s budget. "
        "Check Ollama GPU offload and pgvector index health."
    )
    print(f"\n  ✓ Gate 3: rag_search completed in {elapsed:.3f}s (limit: 2.0s)")


# ── Exit Gate 4: Idempotent ingestion ────────────────────────────────────────

@requires_postgres
def test_exit_gate_4_ingestor_is_idempotent(ensure_ingested):
    """
    GATE 4: Re-running ingest_documents() without force=True does not
    duplicate rows. Row count must be identical before and after second call.
    """
    from app.rag.ingestor import ingest_documents, get_doc_count

    count_before = get_doc_count()
    assert count_before > 0, "Pre-condition: documents must exist before idempotency test"

    # Second ingest call — should skip because rows exist
    ingest_documents(force=False)

    count_after = get_doc_count()
    assert count_after == count_before, (
        f"Idempotency violation: row count changed from {count_before} → {count_after}. "
        "ingest_documents() is creating duplicate rows on repeated calls."
    )
    print(f"\n  ✓ Gate 4: Idempotent — {count_before} rows before, {count_after} rows after second call")


# ── Exit Gate 5: Index recovery after reset (simulates API restart) ───────────

@requires_full_stack
def test_exit_gate_5_index_recovers_after_reset(ensure_ingested):
    """
    GATE 5: After resetting the singleton (simulating API restart), the index
    loads from pgvector without re-ingestion and returns valid results.
    """
    from app.rag import retriever

    # Force the singleton to None — simulates a fresh API process startup
    retriever.reset_index()
    assert retriever._index is None, "reset_index() did not clear the singleton"

    # Now search — should reload from pgvector and return results
    result = asyncio.run(retriever.rag_search("P/E ratio valuation DCF", top_k=3))

    assert retriever._index is not None, (
        "Index was not reloaded from pgvector after reset — check PGVectorStore connection"
    )
    assert result, (
        "After index reset and reload, rag_search returned empty string. "
        "Ensure documents are still in pgvector and nomic-embed-text is running."
    )
    print(f"\n  ✓ Gate 5: Index recovered from pgvector — returned {len(result)} chars without re-ingestion")


# ── Exit Gate 6: fundamental intent includes rag_context in tool_results ──────

@requires_full_stack
def test_exit_gate_6_fundamental_includes_rag_context(ensure_ingested):
    """
    GATE 6: tool_router._handle_fundamental() populates results["rag_context"]
    with a non-None, non-empty string when intent=fundamental and symbol=AAPL.
    """
    from app.graph.nodes.tool_router import _handle_fundamental

    results = asyncio.run(_handle_fundamental("AAPL"))

    assert "rag_context" in results, (
        "rag_context key missing from tool_results for fundamental/AAPL. "
        "Check tool_router._handle_fundamental() — Phase 4 patch may not have applied."
    )
    rag_ctx = results["rag_context"]

    # rag_context should be a non-empty string (not None, not "")
    assert rag_ctx is not None, (
        "rag_context is None — RAG search may have failed silently. "
        "Check retriever logs and ensure seed documents are ingested."
    )
    assert isinstance(rag_ctx, str) and len(rag_ctx) > 20, (
        f"rag_context is too short or wrong type: type={type(rag_ctx)}, len={len(rag_ctx) if rag_ctx else 0}"
    )
    print(f"\n  ✓ Gate 6: fundamental/AAPL rag_context = {len(rag_ctx)} chars")
    print(f"    Snippet: {rag_ctx[:100]}...")


# ── Bonus: Verify Tesla retrieval works too ───────────────────────────────────

@requires_full_stack
def test_bonus_tesla_retrieval(ensure_ingested):
    """
    Bonus: Verify Tesla earnings content is retrievable — confirms multi-document
    corpus is correctly indexed (not just Apple content).
    """
    from app.rag.retriever import rag_search

    result = asyncio.run(rag_search("Tesla Cybertruck delivery Elon Musk guidance", top_k=3))

    assert result, "Tesla retrieval returned empty — seed_docs may not be fully ingested"
    result_lower = result.lower()
    assert any(term in result_lower for term in ["tesla", "cybertruck", "delivery", "elon"]), (
        f"Tesla content not found in retrieval result. Snippet: {result[:200]}"
    )
    print(f"\n  ✓ Bonus: Tesla content retrieved — {len(result)} chars")


# ── Bonus: glossary retrieval ─────────────────────────────────────────────────

@requires_full_stack
def test_bonus_glossary_retrieval(ensure_ingested):
    """
    Bonus: Verify the financial glossary is retrievable via semantic search.
    """
    from app.rag.retriever import rag_search

    result = asyncio.run(rag_search("what is EV/EBITDA enterprise value", top_k=3))

    assert result, "Glossary retrieval returned empty"
    assert "ebitda" in result.lower() or "enterprise value" in result.lower(), (
        f"Glossary content not found. Snippet: {result[:200]}"
    )
    print(f"\n  ✓ Bonus: Financial glossary retrieved — {len(result)} chars")
