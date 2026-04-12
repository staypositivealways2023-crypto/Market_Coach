"""Behavior analysis worker — runs after every voice session.

Triggered as a FastAPI BackgroundTask from POST /api/voice/session/end.

Steps:
  1. Read behavior_events logged for this session from Firestore
  2. Aggregate events into pattern signals
  3. Update coaching_memory strength scores:
       - Reinforcement: +0.15 when pattern is observed again
       - Decay protection: touch last_seen_at to reset decay clock
       - New pattern: create coaching_memory entry at initial strength 0.4

Pattern signals this worker detects:
  - chart_heavy_user      (>= 3 chart/indicator events in session)
  - macro_curious         (macro tool called in session)
  - rapid_topic_switcher  (>= 4 different symbols in one session)
  - risk_checker          (called risk/stop-loss tool)
  - fundamental_focused   (fundamentals tool called >= 2x)
  - lesson_engaged        (lesson-related events present)
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

# Map of pattern_key → (category, human-readable summary)
_PATTERNS: dict[str, tuple[str, str]] = {
    "chart_heavy_user": (
        "style_preference",
        "User frequently uses charts and technical indicators during sessions",
    ),
    "macro_curious": (
        "style_preference",
        "User regularly checks macro/economic data alongside price data",
    ),
    "rapid_topic_switcher": (
        "trading_habit",
        "User tends to jump between multiple symbols within a single session",
    ),
    "risk_checker": (
        "trading_habit",
        "User proactively checks risk/stop-loss levels before trades",
    ),
    "fundamental_focused": (
        "style_preference",
        "User frequently reviews fundamentals alongside technical data",
    ),
    "lesson_engaged": (
        "motivation_pattern",
        "User actively combines learning sessions with market analysis",
    ),
}

_CHART_EVENT_TYPES = {
    "chart_opened",
    "indicator_enabled",
    "indicator_disabled",
    "timeframe_changed",
    "pattern_tapped",
}

_REINFORCEMENT_DELTA = 0.15
_NEW_STRENGTH = 0.4
_MAX_STRENGTH = 1.0


async def run(
    session_id: str,
    uid: str,
    db,
) -> None:
    """Analyze behavior events for the session and update coaching memory."""
    logger.info(f"[behavior_worker] Starting for session {session_id}")

    # ── 1. Read behavior events for this session ───────────────────────────────
    events: list[dict] = []
    try:
        docs = (
            db.collection("users")
            .document(uid)
            .collection("behavior_events")
            .where("session_id", "==", session_id)
            .stream()
        )
        for doc in docs:
            events.append(doc.to_dict())
    except Exception as exc:
        logger.warning(f"[behavior_worker] Failed to read events for {session_id}: {exc}")
        return

    if not events:
        logger.info(f"[behavior_worker] No behavior events for session {session_id}, skipping")
        return

    # ── 2. Aggregate into pattern signals ─────────────────────────────────────
    detected: set[str] = set()

    chart_event_count = sum(
        1 for e in events if e.get("event_type") in _CHART_EVENT_TYPES
    )
    if chart_event_count >= 3:
        detected.add("chart_heavy_user")

    tool_names = [
        e.get("payload", {}).get("tool", "")
        for e in events
        if e.get("event_type") == "tool_called"
    ]
    if any("macro" in t or "fred" in t for t in tool_names):
        detected.add("macro_curious")

    symbols = {
        e.get("payload", {}).get("symbol")
        for e in events
        if e.get("payload", {}).get("symbol")
    }
    if len(symbols) >= 4:
        detected.add("rapid_topic_switcher")

    if any("risk" in t or "stop" in t for t in tool_names):
        detected.add("risk_checker")

    fundamental_calls = sum(1 for t in tool_names if "fundamental" in t or "valuation" in t)
    if fundamental_calls >= 2:
        detected.add("fundamental_focused")

    if any(e.get("screen", "").startswith("lesson") for e in events):
        detected.add("lesson_engaged")

    if not detected:
        logger.info(f"[behavior_worker] No patterns detected for session {session_id}")
        return

    logger.info(f"[behavior_worker] Detected patterns: {detected}")

    # ── 3. Read existing coaching_memory ──────────────────────────────────────
    existing: dict[str, dict] = {}  # pattern_key → {doc_id, strength, evidence_refs}
    try:
        for doc in (
            db.collection("users")
            .document(uid)
            .collection("coaching_memory")
            .stream()
        ):
            d = doc.to_dict()
            summary = d.get("summary", "").lower()
            # Match by checking if summary contains the pattern summary keyword
            for pk, (_, pat_summary) in _PATTERNS.items():
                if pat_summary[:30].lower() in summary:
                    existing[pk] = {
                        "doc_id": doc.id,
                        "strength": d.get("strength", 0.5),
                        "evidence_refs": d.get("evidence_refs", []),
                    }
                    break
    except Exception as exc:
        logger.warning(f"[behavior_worker] Coaching memory read failed for {uid}: {exc}")

    # ── 4. Write updates ───────────────────────────────────────────────────────
    try:
        from google.cloud.firestore import SERVER_TIMESTAMP
        batch = db.batch()
        coaching_col = db.collection("users").document(uid).collection("coaching_memory")

        for pattern_key in detected:
            category, summary = _PATTERNS[pattern_key]

            if pattern_key in existing:
                doc_id = existing[pattern_key]["doc_id"]
                old_strength = existing[pattern_key]["strength"]
                refs = existing[pattern_key]["evidence_refs"]
                new_strength = min(_MAX_STRENGTH, old_strength + _REINFORCEMENT_DELTA)
                updated_refs = list(set(refs + [session_id]))

                ref = coaching_col.document(doc_id)
                batch.set(
                    ref,
                    {
                        "strength": new_strength,
                        "last_seen_at": SERVER_TIMESTAMP,
                        "evidence_refs": updated_refs,
                    },
                    merge=True,
                )
                logger.debug(
                    f"[behavior_worker] Reinforced '{pattern_key}': "
                    f"{old_strength:.2f} → {new_strength:.2f}"
                )
            else:
                mem_id = str(uuid.uuid4())
                ref = coaching_col.document(mem_id)
                batch.set(ref, {
                    "memory_id": mem_id,
                    "category": category,
                    "summary": summary,
                    "evidence_refs": [session_id],
                    "strength": _NEW_STRENGTH,
                    "last_seen_at": SERVER_TIMESTAMP,
                })
                logger.debug(f"[behavior_worker] Created new pattern '{pattern_key}'")

        batch.commit()
        logger.info(
            f"[behavior_worker] Updated {len(detected)} coaching patterns for {uid}"
        )
    except Exception as exc:
        logger.error(f"[behavior_worker] Coaching memory write failed for {uid}: {exc}")

    logger.info(f"[behavior_worker] Completed for session {session_id}")
