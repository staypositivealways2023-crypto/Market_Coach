"""OpenAI Realtime API session bootstrapping service.

Creates short-lived ephemeral tokens (valid ~60 s) that Flutter uses to
open a WebSocket directly to OpenAI Realtime — keeping the permanent API key
server-side only.

OpenAI Realtime session creation docs:
  POST https://api.openai.com/v1/realtime/sessions
  Returns: { client_secret: { value: "ek_...", expires_at: int } }
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone

from openai import AsyncOpenAI

from app.config import settings

logger = logging.getLogger(__name__)

_REALTIME_MODEL = "gpt-4o-realtime-preview"
_DEFAULT_VOICE = "alloy"


class RealtimeSessionService:
    """Thin wrapper around the OpenAI Realtime sessions endpoint."""

    def __init__(self) -> None:
        self._client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

    async def create_ephemeral_token(
        self,
        instructions: str,
        tools: list[dict],
        voice: str = _DEFAULT_VOICE,
    ) -> tuple[str, datetime]:
        """Create a Realtime session and return (ephemeral_token, expires_at).

        The token is valid for ~60 seconds — Flutter must open the WebSocket
        immediately after receiving the bootstrap response.
        """
        if not settings.OPENAI_API_KEY:
            raise RuntimeError(
                "OPENAI_API_KEY is not configured. "
                "Add it to python-backend/.env and redeploy."
            )

        try:
            session = await self._client.beta.realtime.sessions.create(
                model=_REALTIME_MODEL,
                voice=voice,
                instructions=instructions,
                tools=tools if tools else [],
                tool_choice="auto",
                modalities=["audio", "text"],
                input_audio_format="pcm16",
                output_audio_format="pcm16",
                turn_detection={
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 600,
                },
            )

            token: str = session.client_secret.value
            expires_at = datetime.fromtimestamp(
                session.client_secret.expires_at, tz=timezone.utc
            )

            logger.info(
                f"[realtime] Ephemeral token created — model={_REALTIME_MODEL} "
                f"voice={voice} tools={len(tools)} expires={expires_at.isoformat()}"
            )
            return token, expires_at

        except Exception as exc:
            logger.error(f"[realtime] Failed to create session: {exc}")
            raise

    @property
    def model(self) -> str:
        return _REALTIME_MODEL

    @property
    def default_voice(self) -> str:
        return _DEFAULT_VOICE
