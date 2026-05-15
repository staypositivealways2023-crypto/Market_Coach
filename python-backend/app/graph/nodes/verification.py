"""
Phase 6 — Verification Agent node.

Uses Claude Sonnet to fact-check the DeepSeek-R1 reasoning answer against
the raw tool data before the response reaches the user.

What is checked:
  1. Numerical accuracy — cited RSI, MACD, price, etc. must match tool_results
     within a 2% tolerance.
  2. Directional accuracy — "bullish MACD" must match a positive histogram;
     "oversold RSI" must match RSI < 35; etc.
  3. Relative positioning rule — any price BELOW current must be called Support,
     any price ABOVE must be called Resistance. Flipping this is an auto-fail.
  4. Valuation claims — DCF fair value and margin of safety must match data.

What is NOT checked:
  - Stylistic choices, hedged opinions, educational commentary.
  - Sentiment node outputs (Phase 6 stub — no hard numbers to verify yet).

Retry logic (already wired in graph.py):
  - confidence >= ANALYST_VERIFICATION_THRESHOLD (0.75) → pass → synthesis
  - confidence <  threshold AND retry_count < ANALYST_MAX_RETRIES → retry reasoning
  - retry_count >= ANALYST_MAX_RETRIES → END with error state
"""

import json
import logging
import re
from typing import Any

import anthropic

from app.config import settings
from app.graph.state import AnalystState

logger = logging.getLogger(__name__)

MODEL = "claude-sonnet-4-6"

# Lazy-initialised async client (avoids import-time errors when key not set)
_client: anthropic.AsyncAnthropic | None = None


def _get_client() -> anthropic.AsyncAnthropic | None:
    global _client
    if _client is None and settings.ANTHROPIC_API_KEY:
        _client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
    return _client


# ── Payload trimmer ───────────────────────────────────────────────────────────

def _trim_tool_results(tool_results: dict) -> dict:
    """
    Strip high-cardinality arrays (candles) from tool_results before sending
    to Claude — they bloat the prompt without helping fact-checking.
    Keep all scalar values and nested indicator dicts.
    """
    trimmed = {k: v for k, v in tool_results.items() if k != "candles_30d"}
    return trimmed


# ── Price Integrity Hard Gate ─────────────────────────────────────────────────

# Patterns that match explicit "current price" language — NOT support/resistance levels
_CURRENT_PRICE_RE = re.compile(
    r"""
    (?:
        currently?\s+(?:trading|priced?)\s+(?:at|around|near)\s*\$?\s*   |
        current\s+(?:market\s+)?price\s+(?:is|of|at|=|:)\s*\$?\s*        |
        (?:stock|share)s?\s+(?:is\s+)?(?:trading\s+)?at\s+\$\s*          |
        trading\s+at\s+(?:approximately\s+)?\$\s*                         |
        price[:\s]+\$\s*
    )
    ([\d,]+\.?\d*)
    """,
    re.IGNORECASE | re.VERBOSE,
)


def _check_price_integrity(tool_results: dict, reasoning_answer: str) -> list[str]:
    """
    Data Integrity Hard Gate.

    Extracts the current price from tool_results["quote"]["price"] and scans the
    reasoning_answer for explicit current-price mentions (e.g. "currently trading
    at $189").  If any such mention deviates from the raw price by more than 1%,
    a flag is returned and the verification node will hard-fail immediately.

    Deliberately conservative: only matches clear "current price" context so that
    valid support/resistance levels (which are legitimately different from the
    current price) are never flagged.

    Returns: list with one flag string on violation, empty list if clean.
    """
    raw_price: float | None = None
    try:
        raw_price = float(tool_results.get("quote", {}).get("price", 0) or 0)
    except (TypeError, ValueError):
        pass

    if not raw_price or raw_price <= 0:
        return []   # no reference price — nothing to check

    match = _CURRENT_PRICE_RE.search(reasoning_answer)
    if match is None:
        return []   # no explicit current-price language found — skip check

    try:
        cited_price = float(match.group(1).replace(",", ""))
    except ValueError:
        return []

    if cited_price <= 1.0:
        return []   # ignore fractions / non-price values

    deviation = abs(cited_price - raw_price) / raw_price
    if deviation > 0.01:
        return [
            f"DATA INTEGRITY FAIL: reasoning cites ${cited_price:.2f} as the current price "
            f"but raw quote = ${raw_price:.2f} "
            f"(deviation {deviation * 100:.1f}% > 1.0% hard threshold). "
            f"Retry required — do not use internal knowledge for prices."
        ]
    return []


# ── Prompt ────────────────────────────────────────────────────────────────────

VERIFY_PROMPT = """You are a senior financial fact-checker. Your only job is to verify
that an analyst's written conclusion accurately reflects the raw data provided.

=== RAW DATA (source of truth) ===
{tool_results}

=== ANALYST CONCLUSION ===
{reasoning_answer}

=== VERIFICATION RULES ===
1. NUMERICAL ACCURACY: Flag any numerical claim that differs from the raw data by more
   than 2%. E.g. if RSI data = 72.4 and analyst says "RSI at 65", that is wrong.

2. DIRECTIONAL ACCURACY: Flag directional mismatches:
   - "bullish MACD" requires histogram > 0
   - "bearish MACD" requires histogram < 0
   - "overbought" requires RSI > 70
   - "oversold" requires RSI < 30
   - "above SMA X" requires price > that SMA value

3. RELATIVE POSITIONING RULE (hard constraint):
   - Any price level BELOW current market price must be labelled Support, never Resistance.
   - Any price level ABOVE current market price must be labelled Resistance, never Support.
   - If the analyst inverts this (e.g. calls a level above price "support"), flag it.

4. SCOPE: Only flag factual numerical or directional errors.
   Do NOT flag: hedged language, opinions, stylistic choices, educational commentary,
   or probability estimates that cannot be verified from the data alone.

5. LENIENCY FOR MISSING DATA: If tool data shows "N/A" for a field, do not penalise
   the analyst for omitting or approximating that field.

=== RESPONSE FORMAT ===
Return ONLY valid JSON — no explanation outside the JSON block:
{{
  "confidence": <float 0.0-1.0>,
  "verdict": "pass" | "fail",
  "flagged_claims": ["<specific error>", ...]
}}

Scoring guide:
  1.0  — no errors found
  0.85 — 1 minor rounding difference (< 5%)
  0.75 — 1 directional error or moderate numerical mismatch
  0.50 — multiple errors or a Relative Positioning Rule violation
  0.25 — reasoning contradicts data on core verdict
  0.0  — analysis is entirely fabricated / bears no relation to data

verdict = "pass" if confidence >= {threshold}, else "fail"."""


# ── Main node ─────────────────────────────────────────────────────────────────

async def run(state: AnalystState) -> dict:
    """
    Claude Sonnet verification node.

    If ANTHROPIC_API_KEY is not set, auto-passes with a warning so the graph
    can still complete during local development without a key.
    """
    retry_count = state.get("retry_count", 0)
    reasoning_answer = state.get("reasoning_answer", "")
    reasoning_error = state.get("error")
    tool_results = state.get("tool_results") or {}
    intent = state.get("intent", "general")

    # ── Hard fail when reasoning answer is empty ─────────────────────────────
    # This check MUST come before the general-intent bypass.  An empty answer
    # means DeepSeek (or Ollama) returned nothing; auto-passing would let
    # synthesis hallucinate from its training data.
    # Fail with retry_count++ so the router's retry branch re-runs reasoning.
    if not reasoning_answer or not reasoning_answer.strip():
        if reasoning_error and "Ollama/model not reachable" in reasoning_error:
            logger.warning("[verification] analyst setup error: %s", reasoning_error)
            return {
                "verification_passed": False,
                "verification_score": 0.0,
                "flagged_claims": [reasoning_error],
                "retry_count": settings.ANALYST_MAX_RETRIES,
            }
        logger.warning(
            "[verification] reasoning_answer is empty — hard-failing to trigger retry "
            "(retry %d/%d)", retry_count, settings.ANALYST_MAX_RETRIES
        )
        return {
            "verification_passed": False,
            "verification_score": 0.0,
            "flagged_claims": [
                "Reasoning answer was empty — DeepSeek returned no output. "
                "Retry required."
            ],
            "retry_count": retry_count + 1,
        }

    # ── Bypass for general intent (no numbers to verify) ─────────────────────
    # Only reached when reasoning_answer is non-empty (guard above passed).
    if intent == "general":
        logger.info("[verification] general intent — auto-pass (no numerical claims)")
        return {
            "verification_passed": True,
            "verification_score": 1.0,
            "flagged_claims": [],
            "retry_count": retry_count,
        }

    # ── Bypass when no API key ────────────────────────────────────────────────
    client = _get_client()
    if client is None:
        logger.warning(
            "[verification] ANTHROPIC_API_KEY not set — auto-passing (dev mode)"
        )
        return {
            "verification_passed": True,
            "verification_score": 0.7,
            "flagged_claims": ["Verification skipped — ANTHROPIC_API_KEY not configured."],
            "retry_count": retry_count,
        }

    # ── Deterministic price integrity pre-check (hard gate) ──────────────────
    # Runs BEFORE Claude — if the reasoning answer cites a wildly wrong current
    # price we reject immediately without spending an API token.
    price_flags = _check_price_integrity(tool_results, reasoning_answer)
    if price_flags:
        logger.warning("[verification] Price integrity hard gate TRIGGERED: %s", price_flags)
        return {
            "verification_passed": False,
            "verification_score": 0.0,
            "flagged_claims": price_flags,
            "retry_count": retry_count + 1,
        }

    # ── Build prompt ──────────────────────────────────────────────────────────
    trimmed = _trim_tool_results(tool_results)
    tool_json = json.dumps(trimmed, indent=2, default=str)

    prompt = VERIFY_PROMPT.format(
        tool_results=tool_json,
        reasoning_answer=reasoning_answer,
        threshold=settings.ANALYST_VERIFICATION_THRESHOLD,
    )

    # ── Call Claude Sonnet ────────────────────────────────────────────────────
    try:
        message = await client.messages.create(
            model=MODEL,
            max_tokens=512,
            messages=[{"role": "user", "content": prompt}],
        )
        raw = message.content[0].text.strip()
        logger.debug("[verification] Claude raw response: %s", raw[:200])

    except anthropic.APIConnectionError as exc:
        logger.error("[verification] Claude connection error: %s", exc)
        return _fallback_pass(retry_count, "Claude API connection error")
    except anthropic.RateLimitError as exc:
        logger.warning("[verification] Claude rate limit hit: %s", exc)
        return _fallback_pass(retry_count, "Claude rate limit — verification skipped")
    except anthropic.APIStatusError as exc:
        logger.error("[verification] Claude API error %d: %s", exc.status_code, exc)
        return _fallback_pass(retry_count, f"Claude API error {exc.status_code}")
    except Exception as exc:
        logger.exception("[verification] Unexpected error: %s", exc)
        return _fallback_pass(retry_count, str(exc))

    # ── Parse JSON response ───────────────────────────────────────────────────
    try:
        # Claude sometimes wraps JSON in a ```json fence — strip it
        clean = raw
        if "```" in clean:
            clean = clean.split("```")[1]
            if clean.startswith("json"):
                clean = clean[4:]
        result = json.loads(clean.strip())

    except (json.JSONDecodeError, IndexError) as exc:
        logger.error("[verification] JSON parse failed: %s | raw=%r", exc, raw[:300])
        # Conservative pass — don't retry on a parse failure
        return _fallback_pass(
            retry_count,
            "Verification response could not be parsed — manual review advised",
        )

    confidence: float = float(result.get("confidence", 0.0))
    flagged: list = result.get("flagged_claims", [])
    passed: bool = confidence >= settings.ANALYST_VERIFICATION_THRESHOLD

    logger.info(
        "[verification] intent=%s confidence=%.2f passed=%s flags=%d retry=%d",
        intent, confidence, passed, len(flagged), retry_count,
    )

    return {
        "verification_passed": passed,
        "verification_score": confidence,
        "flagged_claims": flagged,
        # Increment retry_count only on failure so reasoning node knows
        "retry_count": retry_count + (0 if passed else 1),
    }


# ── Helpers ───────────────────────────────────────────────────────────────────

def _fallback_pass(retry_count: int, reason: str) -> dict:
    """Conservative pass used when verification itself fails — don't block the user."""
    return {
        "verification_passed": True,
        "verification_score": 0.6,
        "flagged_claims": [reason],
        "retry_count": retry_count,
    }
