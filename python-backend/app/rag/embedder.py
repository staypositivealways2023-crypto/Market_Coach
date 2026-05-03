"""
Embedding model wrapper — nomic-embed-text via Ollama (768 dims, local, free).

Usage:
    from app.rag.embedder import get_embedder
    embed_model = get_embedder()
"""

import logging
from llama_index.embeddings.ollama import OllamaEmbedding
from app.config import settings

logger = logging.getLogger(__name__)


def get_embedder() -> OllamaEmbedding:
    """
    Return a configured OllamaEmbedding instance for nomic-embed-text.

    nomic-embed-text specs:
        - 768 dimensions
        - 8192 token context window
        - Strong performance on financial text retrieval tasks
    """
    logger.debug(
        "[embedder] model=%s base_url=%s",
        settings.ANALYST_EMBED_MODEL,
        settings.OLLAMA_BASE_URL,
    )
    return OllamaEmbedding(
        model_name=settings.ANALYST_EMBED_MODEL,   # "nomic-embed-text"
        base_url=settings.OLLAMA_BASE_URL,          # "http://ollama:11434"
        ollama_additional_kwargs={"mirostat": 0},
    )
