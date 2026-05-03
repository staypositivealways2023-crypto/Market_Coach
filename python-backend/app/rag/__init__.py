"""
app/rag — LlamaIndex + pgvector RAG stack.

Public API (imported by tool_router):
    from app.rag.retriever import rag_search

Ingestion (run once, or with --force to reingest):
    python -m app.rag.ingestor
    python -m app.rag.ingestor --force
"""
