"""
Phase 1 Exit Gate Tests
=======================
Run with:  pytest tests/test_phase1_exit_gate.py -v

ALL 6 checks must pass before moving to Phase 2.
These tests confirm the LangGraph skeleton works end-to-end with stubs.
"""

import httpx
import pytest

BASE = "http://localhost:8000"
QUERY_URL = f"{BASE}/api/analyst/query"
OPENAPI_URL = f"{BASE}/api/openapi.json"


# ── Check 1: POST /api/analyst/query returns HTTP 200 ─────────────────────────

def test_endpoint_returns_200():
    """POST /api/analyst/query must return HTTP 200 for a basic message."""
    resp = httpx.post(
        QUERY_URL,
        json={"message": "Analyze AAPL", "user_id": "phase1_test"},
        timeout=30,
    )
    assert resp.status_code == 200, (
        f"Expected 200, got {resp.status_code}.\nBody: {resp.text[:400]}"
    )


# ── Check 2: Response contains all 5 phase keys ───────────────────────────────

def test_response_has_all_phase_keys():
    """
    Response JSON must include every key produced by the 5 stub nodes,
    even if values are null/stub placeholders.
    """
    resp = httpx.post(
        QUERY_URL,
        json={"message": "What is RSI?", "user_id": "phase1_test"},
        timeout=30,
    )
    assert resp.status_code == 200
    body = resp.json()

    required_keys = [
        # routing / meta
        "thread_id",
        # phase 1 — intent
        "intent",
        "symbol",
        "intent_confidence",
        # phase 3 — reasoning (phase 2 = tool_results, not in response model directly)
        "cot_thinking",
        "reasoning_answer",
        # phase 4 — verification
        "verification_passed",
        "verification_score",
        "flagged_claims",
        # phase 5 — synthesis
        "coach_response",
        "scenario_cards",
        "audio_url",
        # error
        "error",
    ]
    missing = [k for k in required_keys if k not in body]
    assert not missing, f"Missing keys in response: {missing}\nFull body: {body}"


# ── Check 3: All 5 nodes ran (inferred from stub output values) ───────────────

def test_all_stub_nodes_produced_output():
    """
    Each stub node sets a known sentinel value. Verify all 5 ran by
    checking that their outputs are present and non-null.

    intent     → intent="general", intent_confidence=1.0
    tool_router→ (internal state, not surfaced in response — confirmed via no error)
    reasoning  → cot_thinking starts with "STUB:"
    verification→ verification_passed=True, verification_score=1.0
    synthesis  → coach_response starts with "STUB:", scenario_cards has bull/base/bear
    """
    resp = httpx.post(
        QUERY_URL,
        json={"message": "Test all nodes", "user_id": "phase1_test"},
        timeout=30,
    )
    assert resp.status_code == 200
    b = resp.json()

    # intent stub
    assert b["intent"] == "general",          f"intent wrong: {b['intent']}"
    assert b["intent_confidence"] == 1.0,     f"intent_confidence wrong: {b['intent_confidence']}"

    # reasoning stub
    assert b["cot_thinking"] is not None,     "cot_thinking is None — reasoning node did not run"
    assert "STUB" in b["cot_thinking"],        f"Unexpected cot_thinking: {b['cot_thinking']}"
    assert b["reasoning_answer"] is not None, "reasoning_answer is None"

    # verification stub
    assert b["verification_passed"] is True,  "verification_passed should be True from stub"
    assert b["verification_score"] == 1.0,    f"verification_score wrong: {b['verification_score']}"
    assert b["flagged_claims"] == [],          f"flagged_claims should be empty: {b['flagged_claims']}"

    # synthesis stub
    assert b["coach_response"] is not None,   "coach_response is None — synthesis node did not run"
    assert "STUB" in b["coach_response"],      f"Unexpected coach_response: {b['coach_response']}"
    cards = b["scenario_cards"]
    assert cards is not None,                 "scenario_cards is None"
    for key in ("bull", "base", "bear"):
        assert key in cards,                  f"scenario_cards missing '{key}' key"


# ── Check 4: retry_count starts at 0 and is not negative ─────────────────────

def test_retry_count_starts_at_zero():
    """
    The state's retry_count must initialise to 0.
    It is not in the response model but can be inferred: if verification stub
    passes on first try, retry_count stays 0 and the graph does not loop.
    We verify this by confirming no error field is set and the full cycle ran.
    """
    resp = httpx.post(
        QUERY_URL,
        json={"message": "Should not retry", "user_id": "phase1_test"},
        timeout=30,
    )
    assert resp.status_code == 200
    b = resp.json()
    assert b.get("error") is None, (
        f"error is set — graph may have looped or crashed: {b.get('error')}"
    )
    # synthesis ran means retry_count never exceeded max (no retry occurred)
    assert b["coach_response"] is not None, (
        "synthesis did not run — retry loop may have fired unexpectedly"
    )


# ── Check 5: Checkpointer — same thread_id reused without error ───────────────

def test_checkpointer_same_thread_id_accepted():
    """
    Supply an explicit thread_id on two consecutive requests.
    Both must return 200 and echo back the same thread_id.
    This confirms MemorySaver handles repeated thread keys without crashing.
    """
    thread_id = "phase1-checkpointer-test-001"

    for i in range(2):
        resp = httpx.post(
            QUERY_URL,
            json={
                "message": f"Checkpointer test request {i + 1}",
                "user_id": "phase1_test",
                "thread_id": thread_id,
            },
            timeout=30,
        )
        assert resp.status_code == 200, (
            f"Request {i + 1} failed: {resp.status_code} — {resp.text[:200]}"
        )
        returned_id = resp.json().get("thread_id")
        assert returned_id == thread_id, (
            f"Request {i + 1}: expected thread_id={thread_id!r}, got {returned_id!r}"
        )


# ── Check 6: No import errors — endpoint registered in OpenAPI spec ───────────

def test_no_import_errors_endpoint_in_openapi():
    """
    If main.py had any import error the OpenAPI spec would not load.
    Verify /api/analyst/query appears in the spec — confirms clean startup.
    """
    resp = httpx.get(OPENAPI_URL, timeout=5)
    assert resp.status_code == 200, "FastAPI not running — docker-compose up -d api"
    paths = resp.json().get("paths", {})
    assert "/api/analyst/query" in paths, (
        "Analyst route missing from OpenAPI. Check app/main.py includes analyst_router."
    )
    assert "/api/analyst/audio/{file_id}" in paths, (
        "Audio serve route missing from OpenAPI."
    )
