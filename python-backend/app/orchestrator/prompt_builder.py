"""Voice prompt builder — assembles typed instruction blocks for OpenAI Realtime.

This is separate from app/utils/prompt_builder.py (which builds Claude analysis
prompts). This builder produces the OpenAI Realtime `instructions` string that
defines the assistant's persona, rules, and user context for a voice session.

Block order (most to least stable — for prompt caching compatibility):
  1. Base identity
  2. Product rules
  3. Safety
  4. User profile       ← dynamic
  5. Context            ← dynamic (screen / symbol / lesson)
  6. Coaching memory    ← dynamic (top 5 ranked facts)
"""

from __future__ import annotations

from datetime import datetime, timezone

from app.models.memory import CoachingMemoryEntry, ProfileMemoryEntry
from app.models.voice_session import VoiceMode


# ── Static blocks ─────────────────────────────────────────────────────────────

_BASE_IDENTITY = """You are MarketCoach AI — a calm, sharp, and supportive financial learning coach.
You help users understand markets, improve trading decisions, and build investing knowledge.
You are concise by default. You explain simply first, then add depth only if asked.
You use real-world examples and analogies. You never lecture unprompted.
Today's date is {today}."""

_PRODUCT_RULES = """Behaviour rules:
- Use tools for any live price, indicator, macro, or trade data. Never invent facts.
- In Lesson mode: reference the user's active lesson content. Connect concepts to real chart examples.
- In Trade Debrief mode: retrieve the user's actual recent trade. Focus on setup, risk management, execution, and the one key improvement.
- Voice responses must be short (2–4 sentences) unless the user asks for more detail.
- Do not ask more than one clarifying question per turn.
- Do not end every response with a question. Let the user lead.
- Never promise financial returns or guarantee outcomes."""

_SAFETY = """Safety rules:
- Frame all analysis as educational, not personalised financial advice.
- Always distinguish between analysis and certainty.
- Encourage risk management principles (stop-loss, position sizing).
- If a user describes a harmful trade pattern, gently surface it — don't enable it."""

_MODE_CONTEXT = {
    VoiceMode.GENERAL: "Mode: General coaching. Answer questions about markets, indicators, and learning.",
    VoiceMode.LESSON: "Mode: Lesson assistance. The user is actively studying. Help them understand the current lesson concept. Quiz them if appropriate.",
    VoiceMode.TRADE_DEBRIEF: "Mode: Trade debrief. The user wants to review a recent trade. Use the get_last_trade tool. Be constructive and specific.",
}


# ── Dynamic block builders ────────────────────────────────────────────────────

def _build_profile_block(profile: list[ProfileMemoryEntry], user_level: str) -> str:
    lines = [f"- Experience level: {user_level}"]
    for entry in profile:
        lines.append(f"- {entry.key.replace('_', ' ').capitalize()}: {entry.value}")
    return "User profile:\n" + "\n".join(lines)


def _build_context_block(
    screen_context: str,
    active_symbol: str | None,
    active_lesson_id: str | None,
    mode: VoiceMode,
) -> str:
    parts = [_MODE_CONTEXT[mode]]
    if screen_context:
        parts.append(f"Current screen: {screen_context}")
    if active_symbol:
        parts.append(f"Active ticker: {active_symbol.upper()}")
    if active_lesson_id:
        parts.append(f"Active lesson ID: {active_lesson_id}")
    return "Session context:\n" + "\n".join(parts)


def _build_coaching_block(memories: list[CoachingMemoryEntry]) -> str:
    if not memories:
        return ""
    lines = ["Coaching observations about this user (use to personalise responses):"]
    for m in memories:
        lines.append(f"- [{m.category}] {m.summary}")
    return "\n".join(lines)


# ── Main builder ──────────────────────────────────────────────────────────────

class VoicePromptBuilder:
    """Assembles the full `instructions` string for an OpenAI Realtime session."""

    def build(
        self,
        *,
        profile_memory: list[ProfileMemoryEntry],
        coaching_memory: list[CoachingMemoryEntry],
        user_level: str,
        mode: VoiceMode,
        screen_context: str = "",
        active_symbol: str | None = None,
        active_lesson_id: str | None = None,
    ) -> str:
        today = datetime.now(timezone.utc).strftime("%B %d, %Y")

        blocks = [
            _BASE_IDENTITY.format(today=today),
            _PRODUCT_RULES,
            _SAFETY,
            _build_profile_block(profile_memory, user_level),
            _build_context_block(screen_context, active_symbol, active_lesson_id, mode),
        ]

        coaching_block = _build_coaching_block(coaching_memory)
        if coaching_block:
            blocks.append(coaching_block)

        return "\n\n".join(blocks)
