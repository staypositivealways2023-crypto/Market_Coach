"""
Chart Vision Analysis Service — Phase 2

Accepts a base64-encoded chart image and runs it through Claude claude-opus-4-6
with a structured hedge-fund-analyst prompt.

Returns a rich JSON payload with:
  • trend, patterns, S/R levels, volume analysis
  • Bull / Base / Bear scenario card
  • A short 'narration' string optimised for Jarvis voice playback
  • Confidence score (0.0–1.0)

After analysis, the result is stored in ChromaDB as a 'chart_analysis'
memory event so future sessions can reference prior chart reads.
"""

from __future__ import annotations

import base64
import logging
import re
import os
import time
import json
from typing import Optional

from anthropic import AsyncAnthropic

from app.services.chroma_memory_service import ChromaMemoryService

logger = logging.getLogger(__name__)

# Vision-capable model — claude-opus-4-6 has the strongest chart reading
VISION_MODEL = "claude-opus-4-6"
MAX_TOKENS = 2048

_SYSTEM_PROMPT = """\
You are a senior portfolio manager and technical analyst at a top-tier hedge fund. \
You have 20 years of experience reading price charts across equities, crypto, \
commodities, and macro instruments. You are precise, quantitative, and opinionated.

When analysing a chart image you MUST:
1. Identify the asset and timeframe if visible; otherwise state "Unknown".
2. Identify ALL chart patterns present (e.g. bull flag, head & shoulders, \
   double bottom, ascending triangle, cup-and-handle, wedge, ABCD, etc.).
3. Call out exact or approximate support and resistance levels from the chart.
4. Comment on volume if visible — confirm or diverge from price action.
5. Read any visible indicators (RSI, MACD, Bollinger Bands, EMAs, etc.) and \
   give a specific interpretation.
6. Give a probability-weighted scenario card: Bull, Base, Bear with price targets \
   or percentage moves where possible.
7. Give a single directional verdict: Bullish, Bearish, or Neutral — with \
   a confidence percentage.
8. End with a 1–2 sentence voice narration suitable for text-to-speech \
   (no markdown, plain language, punchy).

IMPORTANT: Be factual. If the chart is unclear or low-resolution say so. \
Never fabricate levels that are not visible. \
Use $ for stock/crypto prices and % for moves.

You MUST respond in the following JSON format (no markdown fences, raw JSON only):
{
  "symbol": "<ticker or Unknown>",
  "timeframe": "<e.g. 4H, 1D, 1W or Unknown>",
  "trend": "<Bullish|Bearish|Neutral>",
  "trend_confidence": <0.0–1.0>,
  "patterns": ["<pattern1>", "<pattern2>"],
  "support_levels": ["<level1>", "<level2>"],
  "resistance_levels": ["<level1>", "<level2>"],
  "volume_analysis": "<one sentence>",
  "indicator_readings": ["<reading1>", "<reading2>"],
  "key_signals": ["<signal1>", "<signal2>"],
  "scenario": {
    "bull": "<target + catalyst>",
    "base": "<most likely path>",
    "bear": "<invalidation level + downside>"
  },
  "summary": "<3–5 sentence professional analysis>",
  "narration": "<1–2 sentence voice-ready summary, no markdown>",
  "confidence": <0.0–1.0>
}
"""


class VisionAnalysisService:
    """Analyses chart images using Claude claude-opus-4-6 Vision."""

    def __init__(self) -> None:
        api_key = os.getenv("ANTHROPIC_API_KEY", "")
        if not api_key:
            logger.warning("[vision] ANTHROPIC_API_KEY not set — vision endpoint will fail")
        self._client = AsyncAnthropic(api_key=api_key) if api_key else None
        self._memory = ChromaMemoryService()

    # ── Public API ────────────────────────────────────────────────────────────

    async def analyse(
        self,
        image_b64: str,
        media_type: str = "image/jpeg",
        symbol: Optional[str] = None,
        question: Optional[str] = None,
        uid: Optional[str] = None,
    ) -> dict:
        """
        Run chart vision analysis.

        Args:
            image_b64:  Base64-encoded image data (no data-URI prefix).
            media_type: MIME type — 'image/jpeg' or 'image/png'.
            symbol:     Optional ticker hint from the client (e.g. 'NVDA').
            question:   Optional focus question from the user.
            uid:        Firebase user ID for ChromaDB memory storage.

        Returns:
            Parsed analysis dict (see module docstring for schema).
        """
        if not self._client:
            raise RuntimeError("ANTHROPIC_API_KEY not configured")

        # Validate image size — Claude vision limit is ~5 MB decoded
        raw_bytes = len(base64.b64decode(image_b64 + "=="))
        if raw_bytes > 5_000_000:
            raise ValueError(f"Image too large ({raw_bytes / 1e6:.1f} MB). Max 5 MB.")

        user_content = self._build_user_content(image_b64, media_type, symbol, question)

        logger.info(
            "[vision] Analysing chart — symbol=%s uid=%s bytes=%d",
            symbol or "?", (uid or "?")[:8], raw_bytes,
        )

        t0 = time.monotonic()
        response = await self._client.messages.create(
            model=VISION_MODEL,
            max_tokens=MAX_TOKENS,
            system=_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_content}],
        )
        elapsed = time.monotonic() - t0

        raw_text = response.content[0].text.strip()
        tokens = response.usage.input_tokens + response.usage.output_tokens
        logger.info(
            "[vision] Done in %.1fs — tokens=%d model=%s",
            elapsed, tokens, VISION_MODEL,
        )

        analysis = self._parse_response(raw_text)

        # Override symbol if client supplied one and model said "Unknown"
        if symbol and analysis.get("symbol") in (None, "Unknown", ""):
            analysis["symbol"] = symbol.upper()

        analysis["tokens_used"] = tokens
        analysis["model"] = VISION_MODEL

        # Persist to ChromaDB so voice sessions can reference "last chart read"
        if uid:
            await self._store_memory(uid, analysis)

        return analysis

    # ── Internal helpers ──────────────────────────────────────────────────────

    def _build_user_content(
        self,
        image_b64: str,
        media_type: str,
        symbol: Optional[str],
        question: Optional[str],
    ) -> list:
        """Build the Claude multi-modal message content block."""
        text_parts = []
        if symbol:
            text_parts.append(f"Asset hint: {symbol.upper()}")
        if question:
            text_parts.append(f"User question: {question}")
        text_parts.append("Please analyse this chart image.")

        return [
            {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": media_type,
                    "data": image_b64,
                },
            },
            {
                "type": "text",
                "text": "\n".join(text_parts),
            },
        ]

    def _parse_response(self, raw: str) -> dict:
        """
        Extract JSON from Claude's response.
        Handles rare cases where the model wraps output in markdown fences.
        """
        # Strip markdown code fences if present
        clean = re.sub(r"^```(?:json)?\s*", "", raw, flags=re.MULTILINE)
        clean = re.sub(r"\s*```$", "", clean, flags=re.MULTILINE).strip()

        try:
            return json.loads(clean)
        except json.JSONDecodeError as exc:
            logger.warning("[vision] JSON parse failed: %s — raw=%.200s", exc, raw)
            # Fallback: return a minimal structure with the raw text as summary
            return {
                "symbol": "Unknown",
                "timeframe": "Unknown",
                "trend": "Neutral",
                "trend_confidence": 0.5,
                "patterns": [],
                "support_levels": [],
                "resistance_levels": [],
                "volume_analysis": "",
                "indicator_readings": [],
                "key_signals": [],
                "scenario": {"bull": "", "base": "", "bear": ""},
                "summary": raw[:1000],
                "narration": "Analysis complete. Check the summary for details.",
                "confidence": 0.5,
            }

    async def _store_memory(self, uid: str, analysis: dict) -> None:
        """Persist the chart analysis as a ChromaDB memory event."""
        symbol = analysis.get("symbol", "Unknown")
        trend = analysis.get("trend", "Neutral")
        patterns = ", ".join(analysis.get("patterns", []))
        summary = analysis.get("summary", "")[:400]

        doc = (
            f"Chart analysis — {symbol} ({trend}). "
            f"Patterns: {patterns or 'none identified'}. "
            f"{summary}"
        )

        try:
            self._memory.store(
                uid=uid,
                text=doc,
                category="chart_analysis",
                symbol=symbol if symbol != "Unknown" else None,
            )
            logger.info("[vision] Stored chart memory for uid=%s symbol=%s", uid[:8], symbol)
        except Exception as exc:
            # Non-fatal — analysis still returned to client
            logger.warning("[vision] ChromaDB store failed: %s", exc)
