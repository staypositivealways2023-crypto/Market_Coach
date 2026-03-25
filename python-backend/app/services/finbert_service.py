"""
FinBERT Sentiment Service (Phase C)

Replaces VADER with ProsusAI/finbert — a BERT model fine-tuned on financial text.
FinBERT correctly reads finance language: "beat estimates" (positive),
"guidance cut" (negative), "margin compression" (negative).
VADER treats "beat" as positive in non-financial context but misses "guidance cut".

Enabled via env var: FINBERT_ENABLED=true
Requires: transformers>=4.40.0, torch (CPU version is fine)
RAM: ~500MB for model weights — requires Railway Starter+ plan.

Falls back to VADER automatically when FINBERT_ENABLED is false or model fails to load.
"""

import logging
from typing import Optional

logger = logging.getLogger(__name__)

# Module-level singleton — loaded once, reused across all requests
_pipeline = None
_load_attempted = False


def _load_pipeline():
    """Load FinBERT pipeline once. Returns pipeline or None on failure."""
    global _pipeline, _load_attempted
    if _load_attempted:
        return _pipeline
    _load_attempted = True

    try:
        from transformers import pipeline as hf_pipeline
        logger.info("[finbert] Loading ProsusAI/finbert (first request — may take 30-60s)...")
        _pipeline = hf_pipeline(
            "text-classification",
            model="ProsusAI/finbert",
            tokenizer="ProsusAI/finbert",
            device=-1,          # CPU only — no CUDA required
            top_k=None,         # return all 3 label scores
            truncation=True,
            max_length=512,
        )
        logger.info("[finbert] ProsusAI/finbert loaded successfully")
    except Exception as e:
        logger.warning(f"[finbert] Failed to load model: {e} — will use VADER fallback")
        _pipeline = None

    return _pipeline


class FinBERTService:
    """
    Financial sentiment scoring via ProsusAI/finbert.

    Outputs a score in the same format as VADER (-1.0 to +1.0, label)
    so it is a drop-in replacement for VADER in news_service.py.
    """

    # FinBERT labels → our internal labels
    _LABEL_MAP = {
        "positive": "positive",
        "negative": "negative",
        "neutral":  "neutral",
    }

    def score(self, text: str) -> tuple[float, str]:
        """
        Score a single text string.
        Returns (compound_score, label) in the same format as VADER.
        compound_score: -1.0 (very bearish) to +1.0 (very bullish).
        """
        if not text or not text.strip():
            return 0.0, "neutral"

        pipe = _load_pipeline()
        if pipe is None:
            return 0.0, "neutral"

        try:
            # Truncate long text — FinBERT max is 512 tokens (~400 words)
            text = text[:800]
            results = pipe(text)
            # results: [[{label: 'positive', score: 0.92}, {label: 'negative', ...}, ...]]
            if results and isinstance(results[0], list):
                scores = {r["label"].lower(): r["score"] for r in results[0]}
            elif results and isinstance(results[0], dict):
                scores = {results[0]["label"].lower(): results[0]["score"]}
            else:
                return 0.0, "neutral"

            pos = scores.get("positive", 0.0)
            neg = scores.get("negative", 0.0)
            neu = scores.get("neutral",  0.0)

            # Convert to compound score: positive probability - negative probability
            # Range: -1.0 (all negative) to +1.0 (all positive)
            compound = round(pos - neg, 3)

            if pos > neg and pos > neu:
                label = "positive"
            elif neg > pos and neg > neu:
                label = "negative"
            else:
                label = "neutral"

            return compound, label

        except Exception as e:
            logger.warning(f"[finbert] Inference error: {e}")
            return 0.0, "neutral"

    def score_batch(self, texts: list[str]) -> list[tuple[float, str]]:
        """
        Score multiple texts in a single forward pass (batched for efficiency).
        Falls back to sequential scoring on error.
        """
        if not texts:
            return []

        pipe = _load_pipeline()
        if pipe is None:
            return [(0.0, "neutral")] * len(texts)

        try:
            cleaned = [t[:800] if t else "" for t in texts]
            # Filter empties — keep track of original indices
            indexed = [(i, t) for i, t in enumerate(cleaned) if t.strip()]
            if not indexed:
                return [(0.0, "neutral")] * len(texts)

            batch_texts = [t for _, t in indexed]
            batch_results = pipe(batch_texts, batch_size=min(8, len(batch_texts)))

            results = [(0.0, "neutral")] * len(texts)
            for (orig_idx, _), raw in zip(indexed, batch_results):
                if isinstance(raw, list):
                    scores = {r["label"].lower(): r["score"] for r in raw}
                elif isinstance(raw, dict):
                    scores = {raw["label"].lower(): raw["score"]}
                else:
                    continue

                pos = scores.get("positive", 0.0)
                neg = scores.get("negative", 0.0)
                neu = scores.get("neutral",  0.0)
                compound = round(pos - neg, 3)

                if pos > neg and pos > neu:
                    label = "positive"
                elif neg > pos and neg > neu:
                    label = "negative"
                else:
                    label = "neutral"

                results[orig_idx] = (compound, label)

            return results

        except Exception as e:
            logger.warning(f"[finbert] Batch inference error: {e} — falling back to sequential")
            return [self.score(t) for t in texts]


# Module-level singleton
_finbert_svc: Optional[FinBERTService] = None


def get_finbert_service() -> FinBERTService:
    global _finbert_svc
    if _finbert_svc is None:
        _finbert_svc = FinBERTService()
    return _finbert_svc
