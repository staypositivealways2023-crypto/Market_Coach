"""Context assembler -- reads Firestore and ChromaDB to build user context for session bootstrap.

Phase 1: reads users/{uid} doc for basic profile (level, preferences).
Phase 2: adds voice_profile_memory + coaching_memory from Firestore.
Phase 3: adds ChromaDB semantic recall for richer personalisation.
"""

from __future__ import annotations

import logging
from typing import Optional

from app.models.memory import CoachingMemoryEntry, ProfileMemoryEntry
from app.models.voice_session import VoiceSessionCreateRequest

logger = logging.getLogger(__name__)


class ContextAssembler:
    """Reads Firestore + ChromaDB to assemble all user context needed for session bootstrap."""

    def __init__(self, db) -> None:
        self._db = db

    async def assemble(self, uid: str, request: VoiceSessionCreateRequest) -> dict:
        """Return a context dict used by VoicePromptBuilder and SessionBootstrapOrchestrator."""
        user_level = "beginner"
        profile_memory: list[ProfileMemoryEntry] = []
        coaching_memory: list[CoachingMemoryEntry] = []

        # Read user doc for base profile
        try:
            user_doc = self._db.collection("users").document(uid).get()
            if user_doc.exists:
                data = user_doc.to_dict()
                user_level = data.get("level", "beginner")
        except Exception as exc:
            logger.warning(f"[context_assembler] Failed to read user doc for {uid}: {exc}")

        # Read voice_profile_memory
        try:
            from datetime import datetime, timezone
            mem_docs = (
                self._db.collection("users")
                .document(uid)
                .collection("voice_profile_memory")
                .stream()
            )
            for doc in mem_docs:
                d = doc.to_dict()
                updated_raw = d.get("updated_at")
                if hasattr(updated_raw, "ToDatetime"):
                    updated_dt = updated_raw.ToDatetime().replace(tzinfo=timezone.utc)
                elif hasattr(updated_raw, "toDatetime"):
                    updated_dt = updated_raw.toDatetime().replace(tzinfo=timezone.utc)
                else:
                    updated_dt = datetime.now(timezone.utc)
                profile_memory.append(
                    ProfileMemoryEntry(
                        key=d.get("key", doc.id),
                        value=d.get("value", ""),
                        source=d.get("source", "session_extraction"),
                        confidence=d.get("confidence", 1.0),
                        updated_at=updated_dt,
                    )
                )
        except Exception as exc:
            logger.warning(f"[context_assembler] Failed to read profile_memory for {uid}: {exc}")

        # Read coaching_memory
        try:
            from datetime import datetime, timezone
            coaching_docs = (
                self._db.collection("users")
                .document(uid)
                .collection("coaching_memory")
                .order_by("strength", direction="DESCENDING")
                .limit(20)
                .stream()
            )
            for doc in coaching_docs:
                d = doc.to_dict()
                seen_raw = d.get("last_seen_at")
                if hasattr(seen_raw, "ToDatetime"):
                    seen_dt = seen_raw.ToDatetime().replace(tzinfo=timezone.utc)
                elif hasattr(seen_raw, "toDatetime"):
                    seen_dt = seen_raw.toDatetime().replace(tzinfo=timezone.utc)
                else:
                    seen_dt = datetime.now(timezone.utc)
                coaching_memory.append(
                    CoachingMemoryEntry(
                        memory_id=doc.id,
                        category=d.get("category", "style_preference"),
                        summary=d.get("summary", ""),
                        evidence_refs=d.get("evidence_refs", []),
                        strength=d.get("strength", 0.5),
                        last_seen_at=seen_dt,
                    )
                )
        except Exception as exc:
            logger.warning(f"[context_assembler] Failed to read coaching_memory for {uid}: {exc}")

        # Read ChromaDB semantic memories -- most relevant to current context
        chroma_memories: list[str] = []
        try:
            from app.services.chroma_memory_service import ChromaMemoryService
            query = request.active_symbol or "user trading habits and learning preferences"
            chroma_memories = ChromaMemoryService().recall(uid, query=query, n=8)
        except Exception as exc:
            logger.warning(f"[context_assembler] ChromaDB recall failed for {uid}: {exc}")

        return {
            "uid": uid,
            "user_level": user_level,
            "profile_memory": profile_memory,
            "coaching_memory": coaching_memory,
            "chroma_memories": chroma_memories,
            "mode": request.mode,
            "screen_context": request.screen_context,
            "active_symbol": request.active_symbol,
            "active_lesson_id": request.active_lesson_id,
        }
