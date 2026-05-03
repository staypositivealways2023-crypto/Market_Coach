"""
Vision router — POST /api/analyst/vision

Accepts a chart image (base64) from the Flutter client and returns a
structured hedge-fund-analyst JSON analysis powered by Claude claude-opus-4-6 Vision.

All routes require Firebase token authentication.

POST /api/analyst/vision
    Body: { image_b64, media_type?, symbol?, question? }
    Returns: VisionAnalysisResponse
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.services.vision_analysis_service import VisionAnalysisService
from app.services.voice_auth_service import get_verified_uid

router = APIRouter()
logger = logging.getLogger(__name__)

# Singleton — one client, shared across all requests
_service = VisionAnalysisService()


# ── Request / Response models ─────────────────────────────────────────────────

class VisionAnalysisRequest(BaseModel):
    """Chart image + optional context from the Flutter client."""

    image_b64: str = Field(
        ...,
        description="Base64-encoded image data (no data-URI prefix).",
        min_length=100,
    )
    media_type: str = Field(
        default="image/jpeg",
        description="MIME type: 'image/jpeg' or 'image/png'.",
        pattern=r"^image/(jpeg|png|webp|gif)$",
    )
    symbol: str | None = Field(
        default=None,
        description="Optional ticker hint, e.g. 'NVDA'. Used if the model cannot read the chart label.",
        max_length=20,
    )
    question: str | None = Field(
        default=None,
        description="Optional focus question, e.g. 'Is this a good entry?'",
        max_length=500,
    )


class ScenarioCard(BaseModel):
    bull: str = ""
    base: str = ""
    bear: str = ""


class VisionAnalysisResponse(BaseModel):
    """Structured chart analysis returned to Flutter."""

    symbol: str = "Unknown"
    timeframe: str = "Unknown"
    trend: str = "Neutral"
    trend_confidence: float = 0.5
    patterns: list[str] = []
    support_levels: list[str] = []
    resistance_levels: list[str] = []
    volume_analysis: str = ""
    indicator_readings: list[str] = []
    key_signals: list[str] = []
    scenario: ScenarioCard = ScenarioCard()
    summary: str = ""
    narration: str = ""
    confidence: float = 0.5
    tokens_used: int = 0
    model: str = ""


# ── Route ─────────────────────────────────────────────────────────────────────

@router.post("/vision", response_model=VisionAnalysisResponse)
async def analyse_chart(
    body: VisionAnalysisRequest,
    uid: str = Depends(get_verified_uid),
):
    """
    Analyse a chart image with Claude claude-opus-4-6 Vision.

    The client should:
      1. Pick an image (gallery or camera)
      2. Compress to JPEG, target ≤ 1 MB
      3. Base64-encode the raw bytes (no data-URI prefix)
      4. POST to this endpoint

    Response includes patterns, S/R levels, scenario card, and a
    voice-ready narration string for Jarvis to speak aloud.
    """
    try:
        result = await _service.analyse(
            image_b64=body.image_b64,
            media_type=body.media_type,
            symbol=body.symbol,
            question=body.question,
            uid=uid,
        )
    except ValueError as exc:
        # Image too large, invalid base64, etc.
        raise HTTPException(status_code=422, detail=str(exc))
    except RuntimeError as exc:
        # API key not configured
        raise HTTPException(status_code=503, detail=str(exc))
    except Exception as exc:
        logger.error("[vision] Unexpected error uid=%s: %s", uid[:8], exc, exc_info=True)
        raise HTTPException(status_code=500, detail="Vision analysis failed")

    # Coerce nested dict → ScenarioCard
    scenario_raw = result.get("scenario", {})
    result["scenario"] = ScenarioCard(
        bull=scenario_raw.get("bull", ""),
        base=scenario_raw.get("base", ""),
        bear=scenario_raw.get("bear", ""),
    )

    return VisionAnalysisResponse(**{
        k: result.get(k, VisionAnalysisResponse.model_fields[k].default)
        for k in VisionAnalysisResponse.model_fields
    })
