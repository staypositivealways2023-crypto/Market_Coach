"""Memory extraction worker -- runs after every voice session.

Triggered as a FastAPI BackgroundTask from POST /api/voice/session/end.

Steps:
  1. Build transcript text from transcript_turns
  2. Call Claude to extract structured profile facts + coaching patterns
  3. Upsert extracted facts to Firestore:
       users/{uid}/voice_profile_memory/{key}   (profile facts)
       users/{uid}/coaching_memory/{memory_id}  (coaching patterns)
  4. Store extracted facts in ChromaDB for semantic recall

Claude returns JSON with two arrays:
  - profile_facts:  [{key, value, confidence}]
  - coaching_observations: [{category, summary, confidence}]

Profile fact keys (stable vocab):
  experience_level, primary_market, preferred_examples, risk_tolerance,
  goal, learning_style, trading_style, time_horizon

Coaching categories (stable vocab):
  learning_gap, trading_habit, style_preference, risk_pattern,
  goal, motivation_pattern
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from app.models.voice_session import TranscriptTurn
from app.services.claude_service import ClaudeService

logger = logging.getLogger(__name__)

_EXTRACTION_PROMPT = """You are a memory extractor for MarketCoach AI, a financial coaching assistant.

Given a voice session transcript between a user and the AI coach, extract two types of information:

1. **profile_facts** -- stable facts about who the user is (extract only what is clearly stated or strongly implied):
   - experience_level: "beginner" | "intermediate" | "advanced"
   - primary_market: e.g. "crypto", "stocks", "forex", "mixed"
   - preferred_examples: specific tickers/assets they mentioned or seem focused on
   - risk_tolerance: "conservative" | "moderate" | "aggressive"
   - goal: their main investing/learning goal in one short phrase
   - learning_style: "conceptual" | "example_driven" | "data_driven"
   - trading_style: "day_trader" | "swing_trader" | "long_term_investor" | "learner"
   - time_horizon: e.g. "short_term", "long_term", "mixed"

2. **coaching_observations** -- behavioural patterns observed in this session:
   - category: one of: learning_gap | trading_habit | style_preference | risk_pattern | goal | motivation_pattern
   - summary: one concise sentence describing the observation
   - confidence: 0.0-1.0

Rules:
- Only extract what you actually observed -- do not invent or assume.
- If the session is very short or off-topic, return empty arrays.
- confidence should reflect how clearly the fact/pattern was demonstrated.
- preferred_examples should be a comma-separated string of tickers if multiple.

Return ONLY valid JSON in this exact format (no markdown, no explanation):
{
  "profile_facts": [
    {"key": "experience_level", "value": "intermediate", "confidence": 0.9}
  ],
  "coaching_observations": [
    {"category": "learning_gap", "summary": "User struggled with RSI divergence concept", "confidence": 0.7}
  ]
}"""


async def run(
    session_id: str,
    uid: str,
    transcript_turns: list[TranscriptTurn],
    db,
    claude_svc: Optional[ClaudeService] = None,
) -> None:
    """Extract memory from transcript and write to Firestore + ChromaDB."""
    logger.info(f"[memory_worker] Starting extraction for session {session_id}")

    if not transcript_turns or not claude_svc:
        logger.info(f"[memory_worker] Skipping -- no transcript or claude_svc for {session_id}")
        return

    # 1. Build transcript text
    lines = []
    for turn in transcript_turns:
        prefix = "User:" if turn.role == "user" else "Coach:"
        lines.append(f"{prefix} {turn.text}")
    transcript_text = "\n".join(lines).strip()

    if not transcript_text:
        return

    # 2. Call Claude for extraction
    extracted: dict = {"profile_facts": [], "coaching_observations": []}
    try:
        result = await claude_svc.generate_analysis(
            system_prompt=_EXTRACTION_PROMPT,
            user_prompt=f"Session transcript:\n\n{transcript_text}",
            max_tokens=600,
        )
        raw = result.get("analysis_text", "").strip()
        # Strip markdown fences if present
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        extracted = json.loads(raw)
    except json.JSONDecodeError as exc:
        logger.warning(f"[memory_worker] JSON parse failed for {session_id}: {exc}")
        return
    except Exception as exc:
        logger.warning(f"[memory_worker] Claude extraction failed for {session_id}: {exc}")
        return

    now = datetime.now(timezone.utc)

    # 3a. Upsert profile facts to Firestore
    profile_facts = extracted.get("profile_facts", [])
    if profile_facts:
        try:
            from google.cloud.firestore import SERVER_TIMESTAMP
            batch = db.batch()
            mem_col = db.collection("users").document(uid).collection("voice_profile_memory")
            for fact in profile_facts:
                key = fact.get("key", "").strip()
                value = str(fact.get("value", "")).strip()
                confidence = float(fact.get("confidence", 0.8))
                if not key or not value:
                    continue
                ref = mem_col.document(key)
                batch.set(
                    ref,
                    {
                        "key": key,
                        "value": value,
                        "source": "session_extraction",
                        "confidence": confidence,
                        "updated_at": SERVER_TIMESTAMP,
                    },
                    merge=True,
                )
            batch.commit()
            logger.info(f"[memory_worker] Upserted {len(profile_facts)} profile facts for {uid}")
        except Exception as exc:
            logger.error(f"[memory_worker] Profile fact write failed for {uid}: {exc}")

    # 3b. Upsert coaching observations to Firestore
    coaching_obs = extracted.get("coaching_observations", [])
    if coaching_obs:
        try:
            from google.cloud.firestore import SERVER_TIMESTAMP

            # Read existing coaching_memory to check for duplicates (by summary similarity)
            existing = {}
            try:
                for doc in (
                    db.collection("users")
                    .document(uid)
                    .collection("coaching_memory")
                    .stream()
                ):
                    d = doc.to_dict()
                    existing[doc.id] = d.get("summary", "").lower()
            except Exception:
                pass

            batch = db.batch()
            coaching_col = db.collection("users").document(uid).collection("coaching_memory")

            for obs in coaching_obs:
                category = obs.get("category", "style_preference").strip()
                summary = obs.get("summary", "").strip()
                confidence = float(obs.get("confidence", 0.5))
                if not summary:
                    continue

                # Check for near-duplicate (same first 40 chars after lowercase)
                summary_key = summary.lower()[:40]
                existing_id = next(
                    (k for k, v in existing.items() if v[:40] == summary_key), None
                )

                if existing_id:
                    # Reinforce existing memory -- increase strength by 0.1, cap at 1.0
                    ref = coaching_col.document(existing_id)
                    batch.set(
                        ref,
                        {
                            "strength": min(1.0, existing.get(existing_id + "_strength", 0.5) + 0.1),
                            "last_seen_at": SERVER_TIMESTAMP,
                            "evidence_refs": existing.get(existing_id + "_refs", []) + [session_id],
                        },
                        merge=True,
                    )
                else:
                    # New observation
                    mem_id = str(uuid.uuid4())
                    ref = coaching_col.document(mem_id)
                    batch.set(ref, {
                        "memory_id": mem_id,
                        "category": category,
                        "summary": summary,
                        "evidence_refs": [session_id],
                        "strength": min(1.0, confidence),
                        "last_seen_at": SERVER_TIMESTAMP,
                    })

            batch.commit()
            logger.info(
                f"[memory_worker] Wrote {len(coaching_obs)} coaching observations for {uid}"
            )
        except Exception as exc:
            logger.error(f"[memory_worker] Coaching memory write failed for {uid}: {exc}")

    # 4. Persist extracted facts to ChromaDB for semantic recall
    try:
        from app.services.chroma_memory_service import ChromaMemoryService
        chroma = ChromaMemoryService()
        for fact in profile_facts:
            key = fact.get("key", "").strip()
            value = str(fact.get("value", "")).strip()
            if key and value:
                chroma.store(uid, f"{key}: {value}", category="preference")
        for obs in coaching_obs:
            summary_text = obs.get("summary", "").strip()
            category = obs.get("category", "event")
            if summary_text:
                chroma.store(uid, summary_text, category=category)
    except Exception as exc:
        logger.warning(f"[memory_worker] ChromaDB store failed for {uid}: {exc}")

    logger.info(f"[memory_worker] Completed for session {session_id}")
