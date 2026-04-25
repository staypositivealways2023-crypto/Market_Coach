"""Chat Router — streaming Coach chat via Claude Sonnet"""

import json
import logging
from typing import List, Optional

import anthropic
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from app.config import settings
from app.utils.auth import require_auth
from app.utils.prompt_builder import PromptBuilder
from app.utils.rate_limit import limiter

logger = logging.getLogger(__name__)

router = APIRouter()

# Claude 3.5 Sonnet for chat — quality matters here; Haiku is used for analysis/portfolio
CHAT_MODEL = "claude-3-5-sonnet-20241022"
CHAT_MAX_TOKENS = 1024


class ChatMessage(BaseModel):
    role: str  # "user" or "assistant"
    content: str


class ChatRequest(BaseModel):
    messages: List[ChatMessage]
    user_level: Optional[str] = "beginner"


@router.post("/chat")
@limiter.limit("60/minute")
async def chat(request: Request, body: ChatRequest, uid: str = Depends(require_auth)):
    """
    Streaming Coach chat endpoint.
    Emits SSE chunks: data: {"text": "..."}\n\n
    Terminates with: data: [DONE]\n\n

    Gracefully handles client disconnects by checking request.is_disconnected()
    and breaking the stream loop.
    """
    if not settings.ANTHROPIC_API_KEY:
        raise HTTPException(status_code=503, detail="AI service not configured")

    if not body.messages:
        raise HTTPException(status_code=400, detail="messages must not be empty")

    system_prompt = PromptBuilder.build_system_prompt()
    messages = [{"role": m.role, "content": m.content} for m in body.messages]

    async def stream_response():
        try:
            client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)
            logger.info(f"[chat] streaming to Claude, {len(messages)} messages, model={CHAT_MODEL}")
            async with client.messages.stream(
                model=CHAT_MODEL,
                max_tokens=CHAT_MAX_TOKENS,
                system=system_prompt,
                messages=messages,
            ) as stream:
                async for text in stream.text_stream:
                    # Check if client has disconnected before sending chunk
                    if await request.is_disconnected():
                        logger.info("[chat] Client disconnected, terminating stream")
                        break
                    chunk = json.dumps({"text": text})
                    yield f"data: {chunk}\n\n"
            yield "data: [DONE]\n\n"
            logger.info("[chat] stream complete")
        except anthropic.RateLimitError:
            logger.warning("Claude rate limit hit on /api/chat")
            yield 'data: {"error": "rate_limit"}\n\n'
        except anthropic.APIError as e:
            logger.error(f"Claude API error on /api/chat: {e}")
            yield 'data: {"error": "api_error"}\n\n'
        except Exception as e:
            logger.error(f"Unexpected error on /api/chat: {e}")
            yield 'data: {"error": "server_error"}\n\n'

    return StreamingResponse(
        stream_response(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
