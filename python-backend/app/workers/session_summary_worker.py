"""Post-session summary worker.

Triggered as a FastAPI BackgroundTask from POST /api/voice/session/end.

Steps:
  1. Build a transcript text from transcript_turns
  2. Call ClaudeService to generate a 3-5 sentence session summary
  3. Write summary back to voice_sessions/{session_id}
  4. Store cleaned transcript messages to voice_sessions/{session_id}/messages/

This worker intentionally has no return value — it runs in the background and
logs failures without propagating them to the client.
"""

from __future__ import annotations

import logging
from typing import Optional

from app.models.voice_session import TranscriptTurn
from app.services.claude_service import ClaudeService

logger = logging.getLogger(__name__)

_SYSTEM_PROMPT = """You are a session summariser for MarketCoach AI.
Given a voice coaching session transcript, write a concise 3-5 sentence summary.
Focus on: what the user asked about, what topics were covered, and any notable learning moments or decisions.
Do not include advice. Be factual and brief."""


async def run(
    session_id: str,
    uid: str,
    transcript_turns: list[TranscriptTurn],
    db,
    claude_svc: Optional[ClaudeService] = None,
) -> None:
    """Run the session summary pipeline in the background."""
    logger.info(f"[summary_worker] Starting summary for session {session_id}")

    # ── 1. Build transcript text ───────────────────────────────────────────────
    if not transcript_turns:
        logger.info(f"[summary_worker] No transcript turns for {session_id}, skipping")
        return

    lines = []
    for turn in transcript_turns:
        prefix = "User:" if turn.role == "user" else "Coach:"
        lines.append(f"{prefix} {turn.text}")
    transcript_text = "\n".join(lines)

    # ── 2. Generate summary via Claude ────────────────────────────────────────
    summary = ""
    if claude_svc and transcript_text.strip():
        try:
            result = await claude_svc.generate_analysis(
                system_prompt=_SYSTEM_PROMPT,
                user_prompt=f"Session transcript:\n\n{transcript_text}",
                max_tokens=300,
            )
            summary = result.get("analysis_text", "").strip()
        except Exception as exc:
            logger.warning(f"[summary_worker] Claude summary failed: {exc}")

    # ── 3. Write summary to Firestore ─────────────────────────────────────────
    try:
        from google.cloud.firestore import SERVER_TIMESTAMP
        db.collection("voice_sessions").document(session_id).set(
            {"summary": summary, "ended_at": SERVER_TIMESTAMP},
            merge=True,
        )
    except Exception as exc:
        logger.error(f"[summary_worker] Firestore session update failed: {exc}")
        return

    # ── 4. Store cleaned transcript messages ──────────────────────────────────
    try:
        from google.cloud.firestore import SERVER_TIMESTAMP
        import uuid
        batch = db.batch()
        for turn in transcript_turns:
            msg_id = str(uuid.uuid4())
            ref = (
                db.collection("voice_sessions")
                .document(session_id)
                .collection("messages")
                .document(msg_id)
            )
            batch.set(ref, {
                "message_id": msg_id,
                "role": turn.role,
                "transcript": turn.text,
                "tool_calls": turn.tool_calls,
                "created_at": SERVER_TIMESTAMP,
            })
        batch.commit()
    except Exception as exc:
        logger.error(f"[summary_worker] Transcript message write failed: {exc}")

    logger.info(f"[summary_worker] Completed for session {session_id}")
