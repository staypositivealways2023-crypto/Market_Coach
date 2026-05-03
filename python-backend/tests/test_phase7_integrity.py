"""
Phase 7 — Data Integrity & State Management Tests
==================================================

Tests the three fixes introduced in the integrity pass:

  1. verification.py — empty reasoning_answer must FAIL (not pass)
  2. verification.py — price integrity hard gate fires on > 1% deviation
  3. synthesis.py    — pre-flight guard returns error sentinel on empty answer
  4. synthesis.py    — prompts contain required data-only guardrails
  5. graph.py        — _route_after_verification blocks empty reasoning even
                       when verification_passed=True

Run from python-backend/:
    python -m pytest tests/test_phase7_integrity.py -v
"""

# Stubs for Docker-only packages (langgraph, anthropic, httpx, langchain_ollama)
# and the app.graph package stub are installed by conftest.py before any test
# file is collected, so no setup is needed here.
import asyncio
import pytest


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _run(coro):
    """Run an async coroutine synchronously."""
    return asyncio.get_event_loop().run_until_complete(coro)


def _base_state(reasoning_answer="", retry_count=0, intent="technical",
                verification_passed=True, tool_price=189.50):
    return {
        "user_message": "Is AAPL overbought?",
        "symbol": "AAPL",
        "user_id": "test",
        "thread_id": "test-thread",
        "intent": intent,
        "intent_confidence": 0.9,
        "tool_results": {
            "quote": {"price": tool_price, "symbol": "AAPL"},
            "indicators": {"rsi": {"value": 72.4, "signal": "overbought"}},
        },
        "cot_thinking": None,
        "reasoning_answer": reasoning_answer,
        "verification_passed": verification_passed,
        "verification_score": 0.9 if verification_passed else 0.0,
        "flagged_claims": None,
        "retry_count": retry_count,
        "coach_response": None,
        "scenario_cards": None,
        "audio_url": None,
        "error": None,
    }


# ===========================================================================
# 1. verification.py — empty reasoning_answer must FAIL
# ===========================================================================

class TestVerificationEmptyReasoning:
    """An empty/None/whitespace reasoning_answer must hard-fail so the retry
    loop re-invokes DeepSeek rather than letting synthesis hallucinate."""

    def _verify(self, answer, retry_count=0):
        from app.graph.nodes.verification import run as verify_run
        state = _base_state(reasoning_answer=answer, retry_count=retry_count)
        return _run(verify_run(state))

    def test_empty_string_fails(self):
        r = self._verify("")
        assert r["verification_passed"] is False, "Empty answer must fail"
        assert r["verification_score"] == 0.0
        assert r["retry_count"] == 1

    def test_whitespace_only_fails(self):
        r = self._verify("   \n\t  ")
        assert r["verification_passed"] is False

    def test_none_fails(self):
        r = self._verify(None)
        assert r["verification_passed"] is False
        assert r["retry_count"] == 1

    def test_retry_count_increments_from_nonzero(self):
        r = self._verify("", retry_count=1)
        assert r["retry_count"] == 2

    def test_flagged_claims_explains_reason(self):
        r = self._verify("")
        assert r["flagged_claims"], "flagged_claims must be non-empty"
        joined = " ".join(r["flagged_claims"]).lower()
        assert "empty" in joined or "retry" in joined, (
            f"Flag must mention 'empty' or 'retry', got: {r['flagged_claims']}"
        )


# ===========================================================================
# 2. verification.py — price integrity hard gate
# ===========================================================================

class TestPriceIntegrityGate:
    """_check_price_integrity() must flag > 1% deviations in explicit current-
    price language, and must NOT flag support/resistance level prices."""

    def setup_method(self):
        from app.graph.nodes.verification import _check_price_integrity
        self._check = _check_price_integrity

    def _tool(self, price):
        return {"quote": {"price": price}}

    # --- Should flag --------------------------------------------------------

    def test_flags_wildly_wrong_price(self):
        """$150 cited vs $271.50 raw — 44 % deviation, must flag."""
        answer = "AAPL is currently trading at $150, which signals a bearish trend."
        flags = self._check(self._tool(271.50), answer)
        assert len(flags) == 1, f"Expected 1 flag, got: {flags}"
        assert "DATA INTEGRITY" in flags[0]
        assert "150" in flags[0]
        assert "271" in flags[0]

    def test_flags_1_5_percent_deviation(self):
        """1.5 % — above the 1 % threshold."""
        answer = "Currently trading at $200.00, the stock looks neutral."
        raw    = 203.05   # 1.5 % above $200
        flags  = self._check(self._tool(raw), answer)
        assert len(flags) == 1, f"Expected 1 flag, got: {flags}"

    def test_flags_current_price_is_pattern(self):
        answer = "The current price is $100. RSI suggests overbought conditions."
        flags = self._check(self._tool(115.00), answer)  # 13 % off
        assert len(flags) == 1

    def test_flags_trading_at_pattern(self):
        answer = "Trading at approximately $95.50, the stock faces key resistance."
        flags = self._check(self._tool(200.00), answer)  # massive gap
        assert len(flags) == 1

    # --- Should NOT flag ---------------------------------------------------

    def test_passes_within_1_percent(self):
        """0.5 % is within tolerance — must pass."""
        answer = "AAPL is currently trading at $189.50 and RSI is at 72."
        flags = self._check(self._tool(190.45), answer)  # 0.5 % off
        assert flags == [], f"Unexpected flag within tolerance: {flags}"

    def test_does_not_flag_support_resistance_levels(self):
        """S/R prices are legitimately different from current price."""
        answer = (
            "Key support sits at $170 and resistance is established at $210. "
            "A breakout above $210 would be bullish."
        )
        flags = self._check(self._tool(189.50), answer)
        assert flags == [], (
            f"S/R levels must NOT trigger price integrity gate, got: {flags}"
        )

    def test_no_raw_price_data_skips_check(self):
        answer = "Currently trading at $150."
        flags = self._check({}, answer)  # empty tool_results
        assert flags == []

    def test_no_price_mention_skips_check(self):
        answer = "RSI has reached 78, indicating overbought territory. MACD is positive."
        flags = self._check(self._tool(189.50), answer)
        assert flags == []


# ===========================================================================
# 3. synthesis.py — pre-flight guard
# ===========================================================================

class TestSynthesisPreFlightGuard:
    """synthesis.run() must return the error sentinel immediately when
    reasoning_answer is empty — no LLM calls must be made."""

    _SENTINEL = "Real-time data synchronization error."

    def _synth(self, answer):
        from app.graph.nodes.synthesis import run as synth_run
        state = _base_state(reasoning_answer=answer)
        return _run(synth_run(state))

    def test_empty_returns_sentinel(self):
        r = self._synth("")
        assert r["coach_response"] == self._SENTINEL, (
            f"Expected sentinel, got: {r['coach_response']!r}"
        )

    def test_none_returns_sentinel(self):
        r = self._synth(None)
        assert r["coach_response"] == self._SENTINEL

    def test_whitespace_returns_sentinel(self):
        r = self._synth("   \n  ")
        assert r["coach_response"] == self._SENTINEL

    def test_audio_url_is_none_on_error(self):
        r = self._synth("")
        assert r["audio_url"] is None

    def test_error_field_is_set(self):
        r = self._synth("")
        assert r.get("error"), "error field must be non-empty on pre-flight failure"

    def test_scenario_cards_present_and_structured(self):
        r = self._synth("")
        cards = r["scenario_cards"]
        assert set(cards.keys()) == {"bull", "base", "bear"}, (
            f"All three scenario keys must be present, got: {set(cards.keys())}"
        )
        for case in ("bull", "base", "bear"):
            assert "title"   in cards[case], f"'{case}' card missing 'title'"
            assert "trigger" in cards[case], f"'{case}' card missing 'trigger'"


# ===========================================================================
# 4. synthesis.py — prompt guardrails
# ===========================================================================

class TestSynthesisPromptGuardrails:
    """Both LLM prompts must contain the USE-ONLY-PROVIDED-DATA instruction
    and the error sentinel string."""

    def test_coach_prompt_forbids_internal_knowledge(self):
        from app.graph.nodes.synthesis import COACH_PROMPT
        t = COACH_PROMPT.upper()
        assert "USE ONLY" in t, "COACH_PROMPT must contain 'USE ONLY'"
        assert "TRAINING" in t or "KNOWLEDGE" in t or "INTERNAL" in t, (
            "COACH_PROMPT must forbid use of internal/training knowledge"
        )
        assert "REAL-TIME DATA SYNCHRONIZATION ERROR" in t, (
            "COACH_PROMPT must include the exact error sentinel string"
        )

    def test_scenario_prompt_forbids_internal_knowledge(self):
        from app.graph.nodes.synthesis import SCENARIO_PROMPT
        t = SCENARIO_PROMPT.upper()
        assert "USE ONLY" in t
        assert "TRAINING" in t or "KNOWLEDGE" in t or "INTERNAL" in t
        assert "REAL-TIME DATA SYNCHRONIZATION ERROR" in t

    def test_coach_prompt_has_dean_persona(self):
        from app.graph.nodes.synthesis import COACH_PROMPT
        assert "Dean" in COACH_PROMPT, "Dean persona must be preserved"

    def test_coach_prompt_enforces_sentence_limit(self):
        from app.graph.nodes.synthesis import COACH_PROMPT
        assert "3" in COACH_PROMPT and "4" in COACH_PROMPT, (
            "COACH_PROMPT must specify the 3-4 sentence limit"
        )

    def test_scenario_prompt_has_bull_base_bear(self):
        from app.graph.nodes.synthesis import SCENARIO_PROMPT
        for key in ('"bull"', '"base"', '"bear"'):
            assert key in SCENARIO_PROMPT, f"SCENARIO_PROMPT missing key {key}"

    def test_scenario_prompt_has_error_json_fallback(self):
        from app.graph.nodes.synthesis import SCENARIO_PROMPT
        # Must tell Mistral to return {"error": ...} when data is missing
        assert '"error"' in SCENARIO_PROMPT, (
            "SCENARIO_PROMPT must instruct model to return error JSON when data is absent"
        )


# ===========================================================================
# 5. graph.py — _route_after_verification defense-in-depth
# ===========================================================================

class TestGraphRoutingDefense:
    """_route_after_verification must route to 'error' when reasoning_answer is
    empty, even if verification_passed=True."""

    def _route(self, reasoning_answer, verification_passed=True, retry_count=0):
        from app.graph.graph import _route_after_verification
        state = _base_state(
            reasoning_answer=reasoning_answer,
            verification_passed=verification_passed,
            retry_count=retry_count,
        )
        return _route_after_verification(state)

    def test_empty_reasoning_routes_to_error_when_verified(self):
        route = self._route("", verification_passed=True)
        assert route == "error", (
            f"Empty reasoning must route to 'error' even after verification pass, got '{route}'"
        )

    def test_none_reasoning_routes_to_error_when_verified(self):
        route = self._route(None, verification_passed=True)
        assert route == "error"

    def test_whitespace_reasoning_routes_to_error(self):
        route = self._route("   ", verification_passed=True)
        assert route == "error"

    def test_valid_reasoning_routes_to_synthesis(self):
        route = self._route(
            "AAPL is currently trading at $189. RSI at 72 signals overbought.",
            verification_passed=True,
        )
        assert route == "synthesis", f"Expected 'synthesis', got '{route}'"

    def test_failed_verification_with_retries_remaining_routes_to_retry(self):
        route = self._route("some answer", verification_passed=False, retry_count=0)
        assert route == "retry"

    def test_failed_verification_exhausted_retries_routes_to_error(self):
        from app.config import settings
        route = self._route(
            "some answer",
            verification_passed=False,
            retry_count=settings.ANALYST_MAX_RETRIES,
        )
        assert route == "error"
