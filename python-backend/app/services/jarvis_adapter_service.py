"""Jarvis Adapter Service

Thin async HTTP client that bridges MarketCoach backend to the local Jarvis
REST API (default: http://localhost:7700).

When Ollama/Jarvis is offline, falls back to Claude API (claude-haiku-4-5-20251001)
so the Flutter chat always works as long as ANTHROPIC_API_KEY is set in .env.
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

_TIMEOUT = getattr(settings, "JARVIS_TIMEOUT_SECONDS", 25)

SYSTEM_PROMPT = (
    "You are Jarvis, a helpful AI financial coach for MarketCoach. "
    "You help users understand market data, stocks, crypto, and finance concepts. "
    "Be concise, accurate, and friendly. When asked about a specific stock or crypto "
    "price, remind the user to check the live data in the app. "
    "Do not give specific investment advice or make price predictions."
)


def _client() -> httpx.AsyncClient:
    """Return a new async client pointed at JARVIS_URL."""
    return httpx.AsyncClient(
        base_url=settings.JARVIS_URL,
        timeout=_TIMEOUT,
        headers={"Content-Type": "application/json"},
    )


async def _claude_fallback(query: str, history: list[dict] | None = None) -> str:
    """Use Claude API when Ollama/Jarvis is unavailable.

    Requires ANTHROPIC_API_KEY in .env.
    Uses claude-haiku-4-5-20251001 for fast, low-cost responses.
    """
    api_key = getattr(settings, "ANTHROPIC_API_KEY", "")
    if not api_key:
        return (
            "Jarvis is currently offline and no AI fallback is configured. "
            "Please start Ollama or set ANTHROPIC_API_KEY in your .env file."
        )

    try:
        import anthropic

        client = anthropic.AsyncAnthropic(api_key=api_key)

        messages: list[dict] = []
        if history:
            for turn in history:
                role = turn.get("role", "user")
                content = turn.get("content", "")
                if role in ("user", "assistant") and content:
                    messages.append({"role": role, "content": content})
        messages.append({"role": "user", "content": query})

        response = await client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            messages=messages,
        )
        reply = response.content[0].text
        logger.info(f"[claude_fallback] replied ({len(reply)} chars)")
        return reply

    except Exception as exc:
        logger.error(f"[claude_fallback] failed: {exc}")
        return "I'm having trouble connecting right now. Please try again in a moment."


async def jarvis_health() -> dict:
    """Check if Jarvis API is reachable.

    Returns {"online": True, ...} if either Ollama or Claude API is available.
    """
    try:
        async with _client() as c:
            r = await c.get("/health")
            r.raise_for_status()
            return {"online": True, "detail": r.json(), "model": "ollama"}
    except Exception as exc:
        logger.warning(f"[jarvis_adapter] Ollama offline: {exc}")

    # Claude API fallback available?
    if getattr(settings, "ANTHROPIC_API_KEY", ""):
        logger.info("[jarvis_adapter] Claude API fallback available")
        return {"online": True, "detail": "claude-fallback", "model": "claude-haiku-4-5-20251001"}

    return {"online": False, "detail": "No AI backend available"}


async def jarvis_ask(query: str, history: list[dict] | None = None) -> str:
    """Send a free-form query through Jarvis or Claude fallback.

    Priority:
      1. Local Jarvis/Ollama (fastest, free, grounded data)
      2. Claude API (reliable fallback when Ollama is offline)

    Returns the assistant reply as a plain string.
    """
    payload: dict[str, Any] = {"query": query}
    if history:
        payload["history"] = history

    try:
        async with _client() as c:
            r = await c.post("/ask", json=payload)
            r.raise_for_status()
            data = r.json()
            return data.get("response") or data.get("message") or str(data)
    except httpx.ConnectError:
        logger.info("[jarvis_adapter] Ollama offline — using Claude API fallback")
        return await _claude_fallback(query, history)
    except httpx.TimeoutException:
        logger.warning("[jarvis_adapter] Jarvis timed out — using Claude API fallback")
        return await _claude_fallback(query, history)
    except Exception as exc:
        logger.error(f"[jarvis_adapter] jarvis_ask failed: {exc}")
        return await _claude_fallback(query, history)


async def jarvis_quote(ticker: str) -> dict:
    """Fetch a live price quote from Jarvis."""
    ticker = ticker.upper()
    try:
        async with _client() as c:
            r = await c.get(f"/quote/{ticker}")
            r.raise_for_status()
            return r.json()
    except httpx.ConnectError:
        return {"error": "Jarvis offline"}
    except httpx.HTTPStatusError as exc:
        return {"error": f"Jarvis /quote returned {exc.response.status_code}"}
    except Exception as exc:
        logger.error(f"[jarvis_adapter] jarvis_quote({ticker}) failed: {exc}")
        return {"error": str(exc)}


async def jarvis_indicators(ticker: str) -> dict:
    """Fetch RSI, MACD, and 52-week range from Jarvis."""
    ticker = ticker.upper()
    try:
        async with _client() as c:
            r = await c.get(f"/indicators/{ticker}")
            r.raise_for_status()
            return r.json()
    except httpx.ConnectError:
        return {"error": "Jarvis offline"}
    except httpx.HTTPStatusError as exc:
        return {"error": f"Jarvis /indicators returned {exc.response.status_code}"}
    except Exception as exc:
        logger.error(f"[jarvis_adapter] jarvis_indicators({ticker}) failed: {exc}")
        return {"error": str(exc)}


async def jarvis_analyse(ticker: str, question: str | None = None) -> dict:
    """Request a grounded analysis for a ticker."""
    ticker = ticker.upper()
    payload: dict[str, Any] = {}
    if question:
        payload["question"] = question
    try:
        async with _client() as c:
            r = await c.post(f"/analyse/{ticker}", json=payload)
            r.raise_for_status()
            return r.json()
    except httpx.ConnectError:
        return {"error": "Jarvis offline"}
    except httpx.HTTPStatusError as exc:
        return {"error": f"Jarvis /analyse returned {exc.response.status_code}"}
    except Exception as exc:
        logger.error(f"[jarvis_adapter] jarvis_analyse({ticker}) failed: {exc}")
        return {"error": str(exc)}


async def jarvis_snapshot(ticker: str) -> dict:
    """Combined quote + indicators in one round-trip."""
    quote = await jarvis_quote(ticker)
    if "error" in quote:
        return quote
    indicators = await jarvis_indicators(ticker)
    return {**quote, **indicators, "jarvis_source": True}
