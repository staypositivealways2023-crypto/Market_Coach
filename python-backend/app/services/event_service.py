"""Event service — logs behavior events to Firestore.

All events are written to: users/{uid}/behavior_events/{event_id}

See voicecoachbuild.md event taxonomy for the full list of event_type values.
"""

from __future__ import annotations

import logging
import uuid
from typing import Optional

from app.models.memory import BehaviorEvent

logger = logging.getLogger(__name__)


class EventService:
    def __init__(self, db) -> None:
        self._db = db

    async def log(
        self,
        uid: str,
        event_type: str,
        session_id: Optional[str] = None,
        payload: Optional[dict] = None,
        screen: Optional[str] = None,
    ) -> None:
        """Write one event to users/{uid}/behavior_events/{event_id}."""
        try:
            from google.cloud.firestore import SERVER_TIMESTAMP
            event_id = str(uuid.uuid4())
            self._db.collection("users").document(uid).collection("behavior_events").document(
                event_id
            ).set({
                "event_id": event_id,
                "event_type": event_type,
                "session_id": session_id,
                "screen": screen,
                "payload": payload or {},
                "created_at": SERVER_TIMESTAMP,
            })
        except Exception as exc:
            logger.error(f"[event_service] Failed to log event {event_type} for {uid}: {exc}")

    async def log_batch(self, uid: str, events: list[BehaviorEvent]) -> int:
        """Write multiple events in a Firestore batch."""
        accepted = 0
        try:
            from google.cloud.firestore import SERVER_TIMESTAMP
            batch = self._db.batch()
            for event in events:
                event_id = str(uuid.uuid4())
                ref = (
                    self._db.collection("users")
                    .document(uid)
                    .collection("behavior_events")
                    .document(event_id)
                )
                batch.set(ref, {
                    "event_id": event_id,
                    "event_type": event.event_type,
                    "session_id": event.session_id,
                    "screen": event.screen,
                    "payload": event.payload,
                    "created_at": SERVER_TIMESTAMP,
                })
                accepted += 1
            batch.commit()
        except Exception as exc:
            logger.error(f"[event_service] Batch log failed for {uid}: {exc}")
        return accepted
