"""AnalystState — the single source of truth flowing through every graph node."""

from typing import TypedDict, Optional, List, Literal


class AnalystState(TypedDict):
    """
    Canonical state object for the Analyst Cycle graph.
    Every node reads from and writes to this dict.
    LangGraph merges node return dicts into this state automatically.
    """

    # ── Input ────────────────────────────────────────────────────────────────
    user_message: str
    user_id: str
    thread_id: Optional[str]       # LangGraph checkpointer thread key

    # ── Phase 1: Intent Classification ───────────────────────────────────────
    intent: Optional[Literal["technical", "fundamental", "sentiment", "general"]]
    symbol: Optional[str]          # Extracted ticker (e.g. "AAPL", "BTC")
    intent_confidence: Optional[float]

    # ── Phase 2: Tool Selection & Data Fetch ─────────────────────────────────
    tool_results: Optional[dict]   # Serialised output from all tools called

    # ── Phase 3: DeepSeek-R1 Reasoning ───────────────────────────────────────
    cot_thinking: Optional[str]    # Raw <think>...</think> content (CoT)
    reasoning_answer: Optional[str]  # Final answer after </think>

    # ── Phase 4: Verification ─────────────────────────────────────────────────
    verification_passed: Optional[bool]
    verification_score: Optional[float]
    flagged_claims: Optional[List[str]]
    retry_count: int               # Increments on each failed verification

    # ── Phase 5: Synthesis & Output ──────────────────────────────────────────
    coach_response: Optional[str]      # Dean persona short narration
    scenario_cards: Optional[dict]     # {"bull": {...}, "base": {...}, "bear": {...}}
    audio_url: Optional[str]           # Served MP3 path if Cartesia enabled

    # ── Error Handling ────────────────────────────────────────────────────────
    error: Optional[str]
