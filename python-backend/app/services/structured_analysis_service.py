"""Structured Analysis Service — returns same JSON schema as Flutter EnhancedAIAnalysis."""

import json
import asyncio
import logging
from typing import Optional

import anthropic

from app.config import settings
from app.services.data_fetcher import MarketDataFetcher

logger = logging.getLogger(__name__)

_CRYPTO = {
    "BTC", "ETH", "BNB", "SOL", "ADA", "XRP", "DOGE", "DOT",
    "AVAX", "MATIC", "LINK", "UNI", "LTC", "BCH", "XLM",
}

MODEL = "claude-sonnet-4-6"


class StructuredAnalysisService:
    """Calls Claude with structured JSON prompt identical to the Flutter client."""

    def __init__(self):
        self._fetcher = MarketDataFetcher()
        self._client: Optional[anthropic.Anthropic] = None
        if settings.ANTHROPIC_API_KEY:
            self._client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)

    @property
    def is_configured(self) -> bool:
        return self._client is not None

    async def analyze(self, symbol: str) -> dict:
        """
        Fetch live data + call Claude + return structured JSON dict.
        The dict keys match Flutter's EnhancedAIAnalysis.fromJson.
        """
        if not self.is_configured:
            raise ValueError("ANTHROPIC_API_KEY not configured")

        sym = symbol.upper()

        # Fetch quote in parallel with recent candles
        quote, candles = await asyncio.gather(
            self._fetcher.get_quote(sym),
            self._fetcher.get_candles(sym, interval="1d", limit=30),
            return_exceptions=True,
        )
        if isinstance(quote, Exception):
            quote = None
        if isinstance(candles, Exception):
            candles = []

        price = quote.price if quote else 0.0
        if price == 0:
            raise ValueError(f"Could not fetch price for {symbol}")

        prompt = _build_prompt(sym, price, quote, candles)

        # Call Claude synchronously in executor
        def _call():
            response = self._client.messages.create(
                model=MODEL,
                max_tokens=1024,
                messages=[{"role": "user", "content": prompt}],
            )
            return response.content[0].text

        loop = asyncio.get_event_loop()
        raw = await loop.run_in_executor(None, _call)

        return _parse(raw, price, sym)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _build_prompt(symbol: str, price: float, quote, candles: list) -> str:
    lines = [
        f"You are a financial analyst. Analyze {symbol} and respond ONLY with a JSON object — no explanation, no markdown, no code fences, just raw JSON.",
        "",
        "MARKET DATA:",
        f"Symbol: {symbol}",
        f"Current Price: ${price:.2f}",
    ]

    if quote:
        if quote.change_percent is not None:
            lines.append(f"Today Change: {quote.change_percent:.2f}%")
        if quote.high and quote.low:
            lines.append(f"Day Range: ${quote.low:.2f} - ${quote.high:.2f}")
        if quote.volume:
            lines.append(f"Volume: {quote.volume:,}")

    if candles and len(candles) >= 5:
        year_high = max(c.high for c in candles)
        year_low = min(c.low for c in candles)
        lines.append(f"30-Day Range: ${year_low:.2f} - ${year_high:.2f}")
        first = candles[0].close
        last = candles[-1].close
        change_pct = (last - first) / first * 100
        lines.append(f"30-Day Price Change: {change_pct:.2f}%")

    max_up = price * 1.15
    max_down = price * 0.85

    lines += [
        "",
        f"CRITICAL PRICE CONSTRAINT: Current price is exactly ${price:.2f}.",
        "All price fields MUST be realistic dollar values anchored to this price:",
        f"  price_target: between ${max_down:.2f} and ${max_up:.2f} (within ±15% of current)",
        f"  price_low: must be BELOW ${price:.2f} (downside scenario)",
        f"  price_high: must be ABOVE ${price:.2f} (upside scenario)",
        f"Do NOT use round placeholder numbers like 100, 200, 1000 — use precise values near ${price:.2f}.",
        "",
        "Respond with EXACTLY this JSON structure and nothing else:",
        """{
  "sentiment_score": <integer 0-100, where 0=extremely bearish, 50=neutral, 100=extremely bullish>,
  "recommendation": <one of: "STRONG_BUY", "BUY", "HOLD", "SELL", "STRONG_SELL">,
  "summary": "<2-3 sentence plain-English summary of the current situation>",
  "bullish_factors": ["<specific factor with data>", "<specific factor with data>", "<specific factor with data>"],
  "bearish_factors": ["<specific factor with data>", "<specific factor with data>", "<specific factor with data>"],
  "price_target": <7-day target, a precise number near current price, within ±15%>,
  "price_low": <pessimistic 7-day price below current, within 15% downside>,
  "price_high": <optimistic 7-day price above current, within 15% upside>,
  "risk_level": <one of: "LOW", "MEDIUM", "HIGH", "VERY_HIGH">,
  "risk_explanation": "<1-2 sentences explaining the main risk>",
  "technical_note": "<1 sentence on the key technical signal right now>"
}""",
    ]
    return "\n".join(lines)


def _parse(raw: str, current_price: float, symbol: str) -> dict:
    clean = raw.strip()
    if clean.startswith("```"):
        import re
        clean = re.sub(r"```[a-z]*\n?", "", clean).strip()

    data = json.loads(clean)

    sentiment = int(data.get("sentiment_score", 50))
    sentiment = max(0, min(100, sentiment))

    target = _safe_float(data.get("price_target"))
    low = _safe_float(data.get("price_low"))
    high = _safe_float(data.get("price_high"))

    # Sanitise price target to ±20% of current
    if target is not None:
        min_p, max_p = current_price * 0.80, current_price * 1.20
        if not (min_p <= target <= max_p):
            bias = (sentiment - 50) / 50.0
            target = round(current_price * (1 + bias * 0.07), 2)
    if low is not None and low >= current_price:
        low = round(current_price * 0.96, 2)
    if high is not None and high <= current_price:
        high = round(current_price * 1.04, 2)

    return {
        "symbol": symbol,
        "sentiment_score": sentiment,
        "recommendation": data.get("recommendation", "HOLD"),
        "summary": data.get("summary", ""),
        "bullish_factors": data.get("bullish_factors", []),
        "bearish_factors": data.get("bearish_factors", []),
        "price_target": target,
        "price_low": low,
        "price_high": high,
        "risk_level": data.get("risk_level", "MEDIUM"),
        "risk_explanation": data.get("risk_explanation", ""),
        "technical_note": data.get("technical_note"),
        "current_price": current_price,
    }


def _safe_float(v) -> Optional[float]:
    try:
        return float(v) if v is not None else None
    except (TypeError, ValueError):
        return None
