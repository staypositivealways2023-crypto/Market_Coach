"""
Phase 7 -- Synthesis & Output node.

Responsibilities:
  1. Generate Dean coach persona text (3-4 sentences, verdict-first) via Mistral 7B
  2. Generate Bull / Base / Bear scenario cards via Mistral 7B JSON mode
  3. Call Cartesia TTS -> write WAV to /app/audio_cache/ -> return audio_url
     Audio is served by GET /api/analyst/audio/{file_id} in analyst.py

Cartesia config:
  model      : sonic-3
  API version: 2026-03-01
  format     : wav / pcm_s16le / 44100 Hz
  voice ID   : settings.CARTESIA_VOICE_ID (default: a167e0f3-df7e-4d52-a9c3-f949145efdab)
"""

import json
import logging
import os
import re
import uuid

import httpx

from app.config import settings
from app.graph.state import AnalystState

logger = logging.getLogger(__name__)

AUDIO_DIR = "/app/audio_cache"
CARTESIA_URL = "https://api.cartesia.ai/tts/bytes"

# --------------------------------------------------------------------------
# Prompts
# --------------------------------------------------------------------------

COACH_PROMPT = """You are Dean, a confident but balanced financial coach speaking directly to a client.
Summarize the analysis below in exactly 3-4 sentences.

CRITICAL DATA RULES -- these override everything else:
- USE ONLY the numbers and price levels explicitly stated in the Analysis below.
- NEVER use your internal training knowledge for any price, indicator value, or metric.
- If the Analysis is missing a key number, say so -- do NOT invent or recall a figure.
- If the provided price data looks stale or inconsistent, respond with exactly:
  "Real-time data synchronization error."
- Do NOT use bullet points, headers, or markdown. Plain conversational sentences only.

Format rules:
- Start with the verdict (bullish / bearish / neutral / caution).
- Be direct and specific -- cite the key indicator or metric that drove the verdict.
- End with one actionable suggestion (e.g. watch a level, wait for confirmation).

Symbol: {symbol}
Analysis: {reasoning_answer}"""

SCENARIO_PROMPT = """You are a financial analyst generating scenario cards.
Return ONLY valid JSON with no extra text or markdown fences:
{{
  "bull": {{"title": "Bull Case", "trigger": "...", "target": "...", "probability": "...%"}},
  "base": {{"title": "Base Case", "trigger": "...", "target": "...", "probability": "...%"}},
  "bear": {{"title": "Bear Case", "trigger": "...", "target": "...", "probability": "...%"}}
}}

CRITICAL DATA RULES:
- USE ONLY the price levels, indicator values, and facts stated in the Analysis below.
- NEVER invent price targets from your training knowledge -- derive targets only from the data.
- target: a price level or % move grounded in the provided analysis (e.g. "$210" or "+8%")
- trigger: the specific event or condition in the analysis that confirms this scenario
- probability: three values must sum to approximately 100%
- If the Analysis is empty or contains no actionable data, return:
  {{"error": "Real-time data synchronization error."}}

Symbol: {symbol}
Analysis: {reasoning_answer}"""


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def _trim_to_sentences(text, max_sentences=4):
    """Trim Mistral output to at most max_sentences sentences."""
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    return " ".join(sentences[:max_sentences])


def _extract_json(raw):
    """Strip markdown fences that Mistral sometimes wraps JSON in."""
    match = re.search(r"```(?:json)?\s*([\s\S]*?)```", raw)
    if match:
        return match.group(1).strip()
    return raw.strip()


async def _generate_coach_text(answer, symbol):
    """Call Mistral 7B to produce Dean's 3-4 sentence coaching verdict."""
    from langchain_ollama import OllamaLLM
    llm = OllamaLLM(
        model=settings.ANALYST_INTENT_MODEL,
        base_url=settings.OLLAMA_BASE_URL,
        temperature=0.5,
    )
    prompt = COACH_PROMPT.format(
        symbol=symbol or "this asset",
        reasoning_answer=answer,
    )
    try:
        raw = await llm.ainvoke(prompt)
        return _trim_to_sentences(str(raw).strip(), max_sentences=4)
    except Exception as e:
        logger.error("[synthesis] Coach text generation failed: %s", e)
        return _trim_to_sentences(answer, max_sentences=2)


async def _generate_scenarios(answer, symbol):
    """Call Mistral 7B in JSON mode to produce Bull / Base / Bear cards."""
    from langchain_ollama import OllamaLLM
    llm = OllamaLLM(
        model=settings.ANALYST_INTENT_MODEL,
        base_url=settings.OLLAMA_BASE_URL,
        format="json",
        temperature=0.4,
    )
    prompt = SCENARIO_PROMPT.format(
        symbol=symbol or "this asset",
        reasoning_answer=answer,
    )
    try:
        raw = await llm.ainvoke(prompt)
        cleaned = _extract_json(str(raw))
        parsed = json.loads(cleaned)
        scenarios = {}
        for case in ("bull", "base", "bear"):
            card = parsed.get(case, {})
            scenarios[case] = {
                "title":       card.get("title", f"{case.capitalize()} Case"),
                "trigger":     card.get("trigger", ""),
                "target":      card.get("target", ""),
                "probability": card.get("probability", ""),
            }
        return scenarios
    except json.JSONDecodeError as e:
        logger.warning("[synthesis] Scenario JSON parse failed (%s). Raw: %.200s", e, raw)
        return {
            "bull": {"title": "Bull Case",  "trigger": "", "target": "", "probability": ""},
            "base": {"title": "Base Case",  "trigger": "", "target": "", "probability": ""},
            "bear": {"title": "Bear Case",  "trigger": "", "target": "", "probability": ""},
        }
    except Exception as e:
        logger.error("[synthesis] Scenario generation failed: %s", e)
        return {
            "bull": {"title": "Bull Case",  "trigger": "", "target": "", "probability": ""},
            "base": {"title": "Base Case",  "trigger": "", "target": "", "probability": ""},
            "bear": {"title": "Bear Case",  "trigger": "", "target": "", "probability": ""},
        }


async def _generate_audio(text):
    """
    Call Cartesia TTS API (sonic-3, 2026-03-01) and write the returned WAV
    bytes to AUDIO_DIR.  Returns a URL path served by analyst.py's audio route.
    Returns None on any failure so the graph can continue without audio.
    """
    if not settings.CARTESIA_API_KEY:
        logger.debug("[synthesis] CARTESIA_API_KEY not set -- skipping TTS")
        return None

    if not settings.CARTESIA_VOICE_ID:
        logger.warning("[synthesis] CARTESIA_VOICE_ID not set -- skipping TTS")
        return None

    os.makedirs(AUDIO_DIR, exist_ok=True)
    file_id = str(uuid.uuid4())
    filepath = os.path.join(AUDIO_DIR, f"{file_id}.wav")

    headers = {
        "Cartesia-Version": "2026-03-01",
        "X-API-Key": settings.CARTESIA_API_KEY,
        "Content-Type": "application/json",
    }
    payload = {
        "model_id": "sonic-3",
        "transcript": text,
        "voice": {
            "mode": "id",
            "id": settings.CARTESIA_VOICE_ID,
        },
        "output_format": {
            "container": "wav",
            "encoding": "pcm_s16le",
            "sample_rate": 44100,
        },
        "generation_config": {
            "speed": 1,
            "volume": 1,
        },
    }

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(CARTESIA_URL, json=payload, headers=headers)

        if resp.status_code == 200:
            with open(filepath, "wb") as f:
                f.write(resp.content)
            logger.info(
                "[synthesis] TTS audio written: %s (%d bytes)", filepath, len(resp.content)
            )
            return f"/api/analyst/audio/{file_id}"
        else:
            logger.error(
                "[synthesis] Cartesia TTS returned %d: %.300s",
                resp.status_code,
                resp.text,
            )
            return None

    except httpx.TimeoutException:
        logger.error("[synthesis] Cartesia TTS request timed out after 30s")
        return None
    except Exception as e:
        logger.error("[synthesis] Cartesia TTS unexpected error: %s", e)
        return None


# --------------------------------------------------------------------------
# Main node
# --------------------------------------------------------------------------

async def run(state: AnalystState) -> dict:
    """
    Synthesis node -- called after verification passes.

    Steps:
      1. Pre-flight guard: refuse to synthesize if reasoning_answer is empty
      2. Generate Dean coach speech text  (Mistral 7B, ~2-4s)
      3. Generate Bull/Base/Bear cards    (Mistral 7B JSON mode, ~2-4s)
      4. Cartesia TTS sonic-3            (HTTP call, ~2-5s, optional)
    """
    answer = state.get("reasoning_answer") or ""
    symbol = state.get("symbol") or "this asset"

    logger.info("[synthesis] Starting -- symbol=%s answer_len=%d", symbol, len(answer))

    # Pre-flight guard: refuse to call any LLM if the reasoning answer is empty.
    # An empty answer means DeepSeek failed; synthesizing from nothing would
    # cause Mistral to draw on its training data and hallucinate prices/targets.
    if not answer or not answer.strip():
        logger.error(
            "[synthesis] reasoning_answer is empty -- refusing to synthesize. "
            "Returning error sentinel to prevent hallucination."
        )
        _empty_card = {
            "title": "",
            "trigger": "Insufficient data",
            "target": "N/A",
            "probability": "N/A",
        }
        return {
            "coach_response": "Real-time data synchronization error.",
            "scenario_cards": {
                "bull": {**_empty_card, "title": "Bull Case"},
                "base": {**_empty_card, "title": "Base Case"},
                "bear": {**_empty_card, "title": "Bear Case"},
            },
            "audio_url": None,
            "error": "Synthesis skipped: reasoning answer was empty.",
        }

    # 1. Coach persona text
    coach_text = await _generate_coach_text(answer, symbol)
    logger.info("[synthesis] Coach text (%d chars): %.120s", len(coach_text), coach_text)

    # 2. Scenario cards
    scenarios = await _generate_scenarios(answer, symbol)
    logger.info("[synthesis] Scenario cards generated: %s", list(scenarios.keys()))

    # 3. TTS (non-blocking failure -- audio_url stays None if Cartesia unavailable)
    audio_url = await _generate_audio(coach_text)
    if audio_url:
        logger.info("[synthesis] Audio available at %s", audio_url)
    else:
        logger.info("[synthesis] No audio (TTS skipped or failed)")

    return {
        "coach_response": coach_text,
        "scenario_cards": scenarios,
        "audio_url": audio_url,
    }
