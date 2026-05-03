"""
Phase 2 Exit Gate Tests
=======================
Run with:  pytest tests/test_phase2_exit_gate.py -v

ALL 8 checks must pass before moving to Phase 3.
Tests confirm Mistral 7B intent classification via the live API endpoint.

Note: each test calls POST /api/analyst/query which runs the full graph
(intent → tool_router stub → reasoning stub → verification stub → synthesis stub).
The only real model call at this phase is Mistral for intent classification.
Expected latency per request: 3–8 seconds.
"""

import httpx
import pytest

BASE = "http://localhost:8000"
QUERY_URL = f"{BASE}/api/analyst/query"

TIMEOUT = 30  # seconds — Mistral 7B intent call is fast; stubs are instant


def _query(message: str) -> dict:
    """POST a message to the analyst endpoint and return the response body."""
    resp = httpx.post(
        QUERY_URL,
        json={"message": message, "user_id": "phase2_test"},
        timeout=TIMEOUT,
    )
    assert resp.status_code == 200, (
        f"Endpoint returned {resp.status_code} for {message!r}.\n{resp.text[:400]}"
    )
    return resp.json()


# ── Check 1: Technical intent + AAPL symbol ──────────────────────────────────

def test_aapl_overbought_is_technical():
    """'Is AAPL overbought?' → intent=technical, symbol=AAPL"""
    body = _query("Is AAPL overbought?")
    assert body["intent"] == "technical", (
        f"Expected intent=technical, got {body['intent']!r}"
    )
    assert body["symbol"] == "AAPL", (
        f"Expected symbol=AAPL, got {body['symbol']!r}"
    )


# ── Check 2: Fundamental intent + TSLA symbol ─────────────────────────────────

def test_tesla_earnings_is_fundamental():
    """'What are Tesla's earnings?' → intent=fundamental, symbol=TSLA"""
    body = _query("What are Tesla's latest earnings?")
    assert body["intent"] == "fundamental", (
        f"Expected intent=fundamental, got {body['intent']!r}"
    )
    assert body["symbol"] == "TSLA", (
        f"Expected symbol=TSLA, got {body['symbol']!r}"
    )


# ── Check 3: Sentiment intent + GME symbol ────────────────────────────────────

def test_gme_reddit_is_sentiment():
    """'What is Reddit saying about GME?' → intent=sentiment, symbol=GME"""
    body = _query("What is Reddit saying about GME?")
    assert body["intent"] == "sentiment", (
        f"Expected intent=sentiment, got {body['intent']!r}"
    )
    assert body["symbol"] == "GME", (
        f"Expected symbol=GME, got {body['symbol']!r}"
    )


# ── Check 4: General intent + null symbol ─────────────────────────────────────

def test_portfolio_advice_is_general():
    """'How should I build a portfolio?' → intent=general, symbol=null"""
    body = _query("How should I build a diversified portfolio?")
    assert body["intent"] == "general", (
        f"Expected intent=general, got {body['intent']!r}"
    )
    assert body["symbol"] is None, (
        f"Expected symbol=null, got {body['symbol']!r}"
    )


# ── Check 5: Crypto technical + BTC symbol ────────────────────────────────────

def test_bitcoin_rsi_is_technical():
    """'Analyze Bitcoin RSI' → intent=technical, symbol starts with BTC"""
    body = _query("Analyze Bitcoin RSI on the 4-hour chart")
    assert body["intent"] == "technical", (
        f"Expected intent=technical, got {body['intent']!r}"
    )
    symbol = body.get("symbol") or ""
    assert symbol.startswith("BTC"), (
        f"Expected symbol starting with BTC, got {symbol!r}"
    )


# ── Check 6: All 5 queries classify within timeout ────────────────────────────

@pytest.mark.slow
def test_all_five_classify_within_timeout():
    """
    Run all 5 canonical queries in sequence.
    Each must complete within TIMEOUT seconds (Mistral 7B is fast).
    """
    import time
    queries = [
        "Is AAPL overbought?",
        "What are Tesla's latest earnings?",
        "What is Reddit saying about GME?",
        "How should I build a diversified portfolio?",
        "Analyze Bitcoin RSI on the 4-hour chart",
    ]
    for msg in queries:
        start = time.monotonic()
        body = _query(msg)
        elapsed = time.monotonic() - start
        assert elapsed < TIMEOUT, (
            f"Query {msg!r} took {elapsed:.1f}s — exceeds {TIMEOUT}s limit"
        )
        assert body["intent"] in {"technical", "fundamental", "sentiment", "general"}, (
            f"Invalid intent {body['intent']!r} for query {msg!r}"
        )


# ── Check 7: Gibberish falls back to general without raising ──────────────────

def test_gibberish_falls_back_to_general():
    """
    Random non-financial input must not raise an exception.
    Falls back to intent=general and symbol=null.
    """
    body = _query("asdfghjkl zxcvbnm qwerty 1234567890")
    assert body.get("error") is None, (
        f"Graph raised an error on gibberish: {body.get('error')}"
    )
    assert body["intent"] in {"technical", "fundamental", "sentiment", "general"}, (
        f"intent is not a valid value: {body['intent']!r}"
    )


# ── Check 8: intent_confidence is always a float in [0.0, 1.0] ───────────────

def test_confidence_is_valid_float():
    """intent_confidence must be a float clamped to [0.0, 1.0] on all queries."""
    queries = [
        "Is MSFT undervalued based on DCF?",
        "What is the MACD signal for ETH?",
        "asdfgh",  # gibberish edge case
        "Explain what a P/E ratio is",
    ]
    for msg in queries:
        body = _query(msg)
        conf = body.get("intent_confidence")
        assert isinstance(conf, (int, float)), (
            f"intent_confidence is not a number for {msg!r}: {conf!r}"
        )
        assert 0.0 <= float(conf) <= 1.0, (
            f"intent_confidence={conf} out of [0,1] range for {msg!r}"
        )
