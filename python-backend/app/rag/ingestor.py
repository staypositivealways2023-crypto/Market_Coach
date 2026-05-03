"""
Document ingestion pipeline — chunks seed docs and stores vectors in pgvector.

Idempotent by default: skips ingestion if documents already exist.
Use --force to clear and reingest.

Run once after first docker-compose up:
    python -m app.rag.ingestor

Force re-ingestion (clears all existing docs first):
    python -m app.rag.ingestor --force
"""

import logging
import os
from pathlib import Path
from typing import Optional

from llama_index.core import (
    SimpleDirectoryReader,
    StorageContext,
    VectorStoreIndex,
)
from llama_index.vector_stores.postgres import PGVectorStore

from app.config import settings
from app.rag.embedder import get_embedder

logger = logging.getLogger(__name__)

# Path to the bundled seed corpus (relative to this file)
SEED_DOCS_PATH = Path(__file__).parent / "seed_docs"

# Embed dimension for nomic-embed-text
EMBED_DIM = 768

# The table PGVectorStore creates in postgres (LlamaIndex prefixes with "data_")
_TABLE_NAME = "financial_docs"
_PG_TABLE = f"data_{_TABLE_NAME}"  # actual postgres table name


# ── Vector store factory ──────────────────────────────────────────────────────

def _pg_connection_string() -> str:
    """
    Build a SQLAlchemy-compatible postgresql+psycopg2 connection string.
    Uses urllib.parse.quote_plus() on password to handle any special characters
    (@, /, :, etc.) that would corrupt URL parsing if left raw.
    """
    from urllib.parse import quote_plus
    pw = quote_plus(str(settings.POSTGRES_PASSWORD))
    conn_str = (
        f"postgresql+psycopg2://{settings.POSTGRES_USER}:{pw}"
        f"@{settings.POSTGRES_HOST}:{settings.POSTGRES_PORT}"
        f"/{settings.POSTGRES_DB}"
    )
    logger.debug(
        "[ingestor] postgres connection target: %s@%s:%s/%s",
        settings.POSTGRES_USER,
        settings.POSTGRES_HOST,
        settings.POSTGRES_PORT,
        settings.POSTGRES_DB,
    )
    return conn_str


def build_vector_store() -> PGVectorStore:
    """
    Create a PGVectorStore connected to the Docker postgres service.

    Uses an explicit connection_string (not individual params) to avoid
    LlamaIndex misreassembling the URL from host/user/password parts.

    port is passed explicitly as a string because PGVectorStore.from_params()
    always calls int(port) internally — even when connection_string is provided
    — and would crash with int('None') if port is omitted.
    """
    return PGVectorStore.from_params(
        connection_string=_pg_connection_string(),
        port=str(settings.POSTGRES_PORT),   # guards against int('None') bug
        table_name=_TABLE_NAME,
        embed_dim=EMBED_DIM,
    )


# ── Row-count helpers (psycopg2) ──────────────────────────────────────────────

def _get_conn():
    """
    Return a raw psycopg2 connection using keyword arguments.
    Avoids libpq URI parsing entirely — immune to special characters in
    the password breaking the host field.
    """
    import psycopg2
    return psycopg2.connect(
        host=settings.POSTGRES_HOST,
        port=int(settings.POSTGRES_PORT),
        dbname=settings.POSTGRES_DB,
        user=settings.POSTGRES_USER,
        password=str(settings.POSTGRES_PASSWORD),
        connect_timeout=5,
    )


def get_doc_count() -> int:
    """
    Return the number of vector rows currently stored.
    Returns 0 if the table does not yet exist (first run).
    """
    try:
        conn = _get_conn()
        cur = conn.cursor()
        # Check table existence first — avoids unhandled error on fresh DB
        cur.execute(
            """
            SELECT EXISTS (
                SELECT FROM information_schema.tables
                WHERE table_schema = 'public'
                AND table_name = %s
            );
            """,
            (_PG_TABLE,),
        )
        if not cur.fetchone()[0]:
            cur.close()
            conn.close()
            return 0

        cur.execute(f'SELECT COUNT(*) FROM "{_PG_TABLE}";')
        count = cur.fetchone()[0]
        cur.close()
        conn.close()
        return count
    except Exception as exc:
        logger.warning("[ingestor] Could not query doc count: %s", exc)
        return 0


def _clear_table() -> None:
    """
    Drop the pgvector data table so the next ingest starts clean.
    Called only when force=True.
    """
    try:
        conn = _get_conn()
        cur = conn.cursor()
        cur.execute(f'DROP TABLE IF EXISTS "{_PG_TABLE}" CASCADE;')
        conn.commit()
        cur.close()
        conn.close()
        logger.info("[ingestor] Dropped existing table '%s'", _PG_TABLE)
    except Exception as exc:
        logger.warning("[ingestor] Could not drop table '%s': %s", _PG_TABLE, exc)


# ── Main ingestion entry point ────────────────────────────────────────────────

def ingest_documents(
    docs_path: Optional[str] = None,
    force: bool = False,
) -> VectorStoreIndex:
    """
    Ingest financial documents from docs_path into pgvector.

    Args:
        docs_path: Directory of .txt files to ingest.
                   Defaults to app/rag/seed_docs/.
        force:     If True, drop existing rows and reingest from scratch.
                   If False (default), skip ingestion when rows already exist.

    Returns:
        A VectorStoreIndex backed by the pgvector store.
    """
    if docs_path is None:
        docs_path = str(SEED_DOCS_PATH)

    # ── Settings dump (visible in logs; helps diagnose env var issues) ────────
    logger.info(
        "[ingestor] postgres config: host=%r user=%r db=%r port=%r password_len=%d",
        settings.POSTGRES_HOST,
        settings.POSTGRES_USER,
        settings.POSTGRES_DB,
        settings.POSTGRES_PORT,
        len(str(settings.POSTGRES_PASSWORD)),
    )

    # ── Idempotency check ────────────────────────────────────────────────────
    if not force:
        existing = get_doc_count()
        if existing > 0:
            logger.info(
                "[ingestor] %d document chunks already in pgvector — skipping. "
                "Run with force=True to reingest.",
                existing,
            )
            vector_store = build_vector_store()
            return VectorStoreIndex.from_vector_store(
                vector_store,
                embed_model=get_embedder(),
            )

    # ── Force: clear existing data ───────────────────────────────────────────
    if force:
        _clear_table()

    # ── Load documents from disk ─────────────────────────────────────────────
    if not Path(docs_path).exists():
        raise FileNotFoundError(f"Seed docs directory not found: {docs_path}")

    documents = SimpleDirectoryReader(docs_path).load_data()
    if not documents:
        raise ValueError(f"No documents found in {docs_path}")

    logger.info(
        "[ingestor] Loaded %d document(s) from '%s' — embedding and indexing...",
        len(documents),
        docs_path,
    )

    # ── Build index and write to pgvector ────────────────────────────────────
    vector_store = build_vector_store()
    storage_context = StorageContext.from_defaults(vector_store=vector_store)

    index = VectorStoreIndex.from_documents(
        documents,
        storage_context=storage_context,
        embed_model=get_embedder(),
        show_progress=True,
    )

    final_count = get_doc_count()
    logger.info(
        "[ingestor] Ingestion complete — %d chunks stored in pgvector.",
        final_count,
    )
    return index


# ── CLI entry point ───────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse
    import sys

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    parser = argparse.ArgumentParser(
        description="Ingest seed financial documents into pgvector."
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Drop existing documents and reingest from scratch.",
    )
    parser.add_argument(
        "--docs-path",
        default=None,
        help="Path to directory of .txt files. Defaults to app/rag/seed_docs/.",
    )
    args = parser.parse_args()

    try:
        ingest_documents(docs_path=args.docs_path, force=args.force)
        print("✓ Ingestion complete.")
    except Exception as e:
        print(f"✗ Ingestion failed: {e}", file=sys.stderr)
        sys.exit(1)
