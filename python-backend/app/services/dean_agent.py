"""
Dean Agent — Phase 2 Memory Layer

Detects behavioural patterns from the non-voice analysis flow and returns a
one-line coaching nudge to surface in the Flutter UI.

Pattern detection logic (rule-based, no ML):
  1. Frequency pattern  — user has analysed the same symbol 3+ times in 7 days
                          without completing the relevant lesson
  2. Signal gap         — current RSI/MACD signal maps to an incomplete lesson
  3. Asset-class gap    — user checks crypto repeatedly but hasn't studied a
                          volatility or crypto-specific lesson

Nudges are short (≤120 chars) and always actionable.
They are completely optional — if Firestore is unavailable or the user has no
gaps, the nudge is None and the UI shows nothing extra.

Storage:
  Reads  from  users/{uid}/lesson_progress/{lessonId}   (existing schema)
  Writes to    users/{uid}/behavior_events/{auto_id}     (existing schema)
  Reads  from  users/{uid}/behavior_events               (event log query)
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

logger = logging.getLogger(__name__)

# ── Symbol → lesson topic mapping ─────────────────────────────────────────────
# Maps a ticker to the Firestore lesson ID (or topic key) most relevant to it.
# Lesson IDs must match what's actually in your Firestore `lessons` collection.
# Add more as you create new lessons.
_SYMBOL_TO_LESSON: dict[str, str] = {
    # Crypto
    "BTC":      "crypto_volatility",
    "ETH":      "crypto_volatility",
    "SOL":      "crypto_volatility",
    "BNB":      "crypto_volatility",
    "XRP":      "crypto_volatility",
    "ADA":      "crypto_volatility",
    "DOGE":     "crypto_volatility",
    # High-growth / volatile stocks
    "TSLA":     "growth_investing",
    "NVDA":     "growth_investing",
    "AMD":      "growth_investing",
    # Large-cap fundamentals
    "AAPL":     "fundamental_analysis",
    "MSFT":     "fundamental_analysis",
    "GOOGL":    "fundamental_analysis",
    "AMZN":     "fundamental_analysis",
    "META":     "fundamental_analysis",
}

# ── Signal → lesson topic mapping ─────────────────────────────────────────────
# Maps a live technical signal from the signal engine to a lesson topic.
_SIGNAL_TO_LESSON: dict[str, str] = {
    "OVERSOLD":        "rsi_basics",
    "OVERBOUGHT":      "rsi_basics",
    "BULLISH_CROSS":   "macd_basics",
    "BEARISH_CROSS":   "macd_basics",
    "BULLISH":         "macd_basics",
    "BEARISH":         "macd_basics",
    "PRICE_BELOW_ALL": "moving_averages",
    "PRICE_ABOVE_ALL": "moving_averages",
    "PRICE_ABOVE_20_50": "moving_averages",
    "PRICE_BELOW_20_50": "moving_averages",
}

# ── Human-readable lesson names ────────────────────────────────────────────────
_LESSON_NAMES: dict[str, str] = {
    "crypto_volatility":   "Understanding Crypto Volatility",
    "growth_investing":    "Growth Investing Fundamentals",
    "fundamental_analysis":"Reading Financial Statements",
    "rsi_basics":          "RSI — Spotting Overbought & Oversold",
    "macd_basics":         "MACD — Trend & Momentum Signals",
    "moving_averages":     "Moving Averages & EMA Stacks",
}

# ── Topic key → GuidedLesson.id mapping ───────────────────────────────────────
# Maps the topic keys above to the actual lesson IDs defined in LessonRegistry.
# Flutter uses this to navigate directly to GuidedLessonScreen(lesson).
_TOPIC_TO_GUIDED_ID: dict[str, str] = {
    "rsi_basics":          "rsi_intro_v1",
    "macd_basics":         "i-02-macd",
    "moving_averages":     "b-04-support-resistance",
    "crypto_volatility":   "b-01-candlestick",    # closest available lesson
    "growth_investing":    "b-11-risk-basics",     # closest available lesson
    "fundamental_analysis":"b-11-risk-basics",     # closest available lesson
}

# ── Frequency threshold ────────────────────────────────────────────────────────
_FREQUENCY_THRESHOLD = 3   # same symbol N+ times in 7 days triggers nudge
_LOOKBACK_DAYS        = 7


async def get_coaching_nudge(
    uid: str,
    symbol: str,
    rsi_signal: Optional[str],
    macd_signal: Optional[str],
    ema_stack: Optional[str],
    db,                      # google.cloud.firestore.AsyncClient or sync Client
) -> tuple[Optional[str], Optional[str]]:
    """Returns (nudge_text, guided_lesson_id) — both may be None."""
    """
    Return a short coaching nudge string, or None if no gap is detected.

    Args:
        uid:         Firebase user ID
        symbol:      Ticker being analysed (e.g. "BTC", "AAPL")
        rsi_signal:  From IndicatorSignals (OVERSOLD | NEUTRAL | OVERBOUGHT)
        macd_signal: From IndicatorSignals (BULLISH_CROSS | BEARISH_CROSS …)
        ema_stack:   From IndicatorSignals (PRICE_ABOVE_ALL | MIXED …)
        db:          Firestore client (sync or async — handled below)
    """
    if not uid or uid in ("dev_user", "anonymous"):
        return None, None

    try:
        # ── 1. Count how often user has analysed this symbol in last 7 days ──
        view_count = await _count_recent_views(uid, symbol, db)

        # ── 2. Determine the most relevant lesson for this symbol + signals ──
        lesson_id = _pick_lesson(symbol, rsi_signal, macd_signal, ema_stack)
        if not lesson_id:
            return None, None

        lesson_name   = _LESSON_NAMES.get(lesson_id, lesson_id)
        guided_id     = _TOPIC_TO_GUIDED_ID.get(lesson_id)  # may be None

        # ── 3. Check if user has already completed that lesson ────────────────
        progress_pct = await _get_lesson_progress(uid, lesson_id, db)
        if progress_pct >= 100:
            return None, None  # already done — no nudge needed

        # ── 4. Choose nudge based on pattern ──────────────────────────────────
        if view_count >= _FREQUENCY_THRESHOLD and progress_pct == 0:
            return (
                f"💡 You've checked {symbol} {view_count}x this week — "
                f"'{lesson_name}' covers this setup. Ready to learn it?"
            ), guided_id

        if view_count >= _FREQUENCY_THRESHOLD and progress_pct > 0:
            return (
                f"💡 {symbol} again! You're {progress_pct}% through "
                f"'{lesson_name}' — finish it to read this chart better."
            ), guided_id

        # Signal-gap nudge (even on first view, if signal matches a gap)
        signal_lesson = _signal_lesson(rsi_signal, macd_signal, ema_stack)
        if signal_lesson and signal_lesson == lesson_id and progress_pct < 50:
            signal_label = _signal_label(rsi_signal, macd_signal, ema_stack)
            return (
                f"💡 {signal_label} detected on {symbol}. "
                f"'{lesson_name}' explains exactly what to do next."
            ), guided_id

    except Exception as exc:
        logger.warning(f"[dean_agent] nudge generation failed for {uid}/{symbol}: {exc}")

    return None, None


async def record_analysis_event(
    uid: str,
    symbol: str,
    signal_label: str,
    scenario_label: str,
    db,
) -> None:
    """
    Fire-and-forget: write a behavior_event to Firestore.
    Reuses the existing users/{uid}/behavior_events schema from the voice system.
    Safe to call without awaiting — swallows all exceptions.
    """
    if not uid or uid in ("dev_user", "anonymous"):
        return
    try:
        from google.cloud.firestore import SERVER_TIMESTAMP  # type: ignore
        event_ref = (
            db.collection("users")
            .document(uid)
            .collection("behavior_events")
            .document()
        )
        event_ref.set({
            "event_type":     "symbol_analysed",
            "screen":         "analysis",
            "payload": {
                "symbol":         symbol,
                "signal_label":   signal_label,
                "scenario_label": scenario_label,
            },
            "created_at": SERVER_TIMESTAMP,
        })
        logger.debug(f"[dean_agent] recorded symbol_analysed event for {uid}/{symbol}")
    except Exception as exc:
        logger.warning(f"[dean_agent] failed to record event for {uid}/{symbol}: {exc}")


# ── Private helpers ───────────────────────────────────────────────────────────

async def _count_recent_views(uid: str, symbol: str, db) -> int:
    """Count how many times uid has analysed symbol in the last 7 days."""
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(days=_LOOKBACK_DAYS)
        query = (
            db.collection("users")
            .document(uid)
            .collection("behavior_events")
            .where("event_type", "==", "symbol_analysed")
            .where("payload.symbol", "==", symbol.upper())
            .where("created_at", ">=", cutoff)
        )
        docs = query.stream()
        count = sum(1 for _ in docs)
        return count
    except Exception as exc:
        logger.warning(f"[dean_agent] _count_recent_views error: {exc}")
        return 0


async def _get_lesson_progress(uid: str, lesson_id: str, db) -> int:
    """
    Return lesson completion percentage (0–100) from Firestore.
    Uses the existing users/{uid}/lesson_progress/{lessonId} schema.
    Returns 0 if no progress record exists.
    """
    try:
        doc = (
            db.collection("users")
            .document(uid)
            .collection("lesson_progress")
            .document(lesson_id)
            .get()
        )
        if not doc.exists:
            return 0
        data = doc.to_dict() or {}
        if data.get("completed"):
            return 100
        current = data.get("current_screen", 0)
        total   = data.get("total_screens", 1)
        if total <= 0:
            return 0
        return int(min(100, (current / total) * 100))
    except Exception as exc:
        logger.warning(f"[dean_agent] _get_lesson_progress error: {exc}")
        return 0


def _pick_lesson(
    symbol: str,
    rsi_signal: Optional[str],
    macd_signal: Optional[str],
    ema_stack: Optional[str],
) -> Optional[str]:
    """Pick the single most relevant lesson ID for this symbol + signals combo."""
    # Signal gap takes priority over asset-class lesson
    sig = _signal_lesson(rsi_signal, macd_signal, ema_stack)
    if sig:
        return sig
    # Fall back to asset/symbol-level lesson
    return _SYMBOL_TO_LESSON.get(symbol.upper())


def _signal_lesson(
    rsi_signal: Optional[str],
    macd_signal: Optional[str],
    ema_stack: Optional[str],
) -> Optional[str]:
    """Return lesson ID for the most interesting current signal, or None."""
    for sig in (rsi_signal, macd_signal, ema_stack):
        if sig and sig.upper() in _SIGNAL_TO_LESSON:
            return _SIGNAL_TO_LESSON[sig.upper()]
    return None


def _signal_label(
    rsi_signal: Optional[str],
    macd_signal: Optional[str],
    ema_stack: Optional[str],
) -> str:
    """Human-readable label for the most prominent current signal."""
    labels = {
        "OVERSOLD":         "Oversold RSI",
        "OVERBOUGHT":       "Overbought RSI",
        "BULLISH_CROSS":    "MACD bullish cross",
        "BEARISH_CROSS":    "MACD bearish cross",
        "PRICE_BELOW_ALL":  "Price below all EMAs",
        "PRICE_ABOVE_ALL":  "Price above all EMAs",
    }
    for sig in (rsi_signal, macd_signal, ema_stack):
        if sig and sig.upper() in labels:
            return labels[sig.upper()]
    return "Signal"
