"""
/api/analyse  — Phase 9 CrewAI Agent Swarm + Phase 3+4 Signal Engine.

Orchestrates all intelligence layers:
  1. Data Ingestion      → candles + quote
  2. Signal Engine       → composite_score + signal_label
  3. Probability Engine  → ATR price range, risk/reward, stop-loss
  4. News sentiment      → sentiment score + headlines
  5. Fundamentals        → P/E, revenue growth (stocks only)
  6. CrewAI Swarm        → 4-agent synthesis (streamed via SSE)
  7. Claude synthesis    → plain-English narrative (fallback)
"""

import json
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Request
from fastapi.responses import StreamingResponse
import asyncio
import logging

from app.services.data_fetcher import MarketDataFetcher
from app.services.indicator_service import TechnicalIndicatorService
from app.services.signal_engine import SignalEngine
from app.services.prediction_engine import PredictionEngine
from app.services.news_service import NewsService
from app.services.fundamental_service import FundamentalService
from app.services.correlation_engine import CorrelationEngine
from app.services.pattern_engine import PatternEngine
from app.services.claude_service import ClaudeService
from app.services.fred_service import FredService
from app.services.dean_agent import get_coaching_nudge, record_analysis_event
from app.utils.prompt_builder import PromptBuilder
from app.utils.cache import cache_manager
from app.utils.auth import require_auth
from app.utils.rate_limit import limiter
from app.models.signals import AnalyseResponse, Scenarios, ScenarioCase

# Firestore client (lazy — only initialised if Firebase is configured)
def _get_db():
    try:
        import firebase_admin
        import firebase_admin.firestore
        if firebase_admin._apps:
            return firebase_admin.firestore.client()
    except Exception:
        pass
    return None

router = APIRouter()
logger = logging.getLogger(__name__)

# Service singletons
_data_fetcher       = MarketDataFetcher()
_indicator_svc      = TechnicalIndicatorService()
_signal_engine      = SignalEngine()
_prediction_engine  = PredictionEngine()
_news_svc           = NewsService()
_fundamental_svc    = FundamentalService()
_correlation_engine = CorrelationEngine()
_pattern_engine     = PatternEngine()
_claude_svc         = ClaudeService()
_fred_svc           = FredService()

# Cache TTL: 1 hour (analysis is expensive + data doesn't change every minute)
_CACHE_TTL = 3600


@router.post("/analyse/{symbol}", response_model=AnalyseResponse)
@router.get("/analyse/{symbol}", response_model=AnalyseResponse)
@limiter.limit("10/minute")
async def analyse_symbol(
    request: Request,
    symbol: str,
    interval: str = "1d",
    user_level: str = "beginner",
    uid: str = Depends(require_auth),
):
    """
    Full 5-layer analysis for a symbol.

    Query params:
      interval   – candlestick interval (1m/5m/15m/1h/4h/1d)  default: 1d
      user_level – beginner | intermediate | advanced           default: beginner
    """
    symbol = symbol.upper()
    cache_key = f"analyse_v6:{symbol}:{interval}"

    # ── Cache check ──────────────────────────────────────────────────────────
    cached = cache_manager.get(cache_key)
    if cached:
        try:
            cached["is_cached"] = True
            return AnalyseResponse(**cached)
        except Exception as e:
            logger.warning(f"[analyse] Cache deserialisation failed for {symbol}, recomputing: {e}")
            cache_manager.delete(cache_key)

    logger.info(f"[analyse] {symbol} interval={interval} level={user_level}")

    # ── Layer 1: Data ingestion ───────────────────────────────────────────────
    candles = await _data_fetcher.get_candles(symbol, interval=interval, limit=200)
    quote   = await _data_fetcher.get_quote(symbol)

    quote_dict = {}
    if quote:
        quote_dict = {
            "price":          quote.price,
            "change":         quote.change,
            "change_percent": quote.change_percent,
            "high":           quote.high,
            "low":            quote.low,
            "volume":         quote.volume,
        }

    # ── Layer 2: Signal engine ────────────────────────────────────────────────
    indicators = None
    if candles and len(candles) >= 26:
        indicators = _indicator_svc.calculate_indicators(
            symbol=symbol,
            candles=candles,
            current_price=quote.price if quote else None,
        )

    signals = _signal_engine.run(
        candles=candles or [],
        indicators=indicators,
    )

    # ── Layer 3: Probability Engine ───────────────────────────────────────────
    prediction = _prediction_engine.calculate(
        candles=candles or [],
        signals=signals,
        current_price=quote.price if quote else None,
        interval=interval,
    )

    # ── Scenario probabilities (computed from score + ATR targets) ───────────
    scenarios = _build_scenarios(signals, prediction)

    # ── Layer 4: News sentiment ───────────────────────────────────────────────
    news = []
    try:
        news = await _news_svc.get_news(symbol, limit=5)
        news = [n.to_dict() if hasattr(n, "to_dict") else (n.dict() if hasattr(n, "dict") else vars(n)) for n in news]
    except Exception as e:
        logger.warning(f"[analyse] News fetch failed for {symbol}: {e}")

    # ── Layer 4: Fundamentals (stocks only) ──────────────────────────────────
    fundamentals = None
    is_crypto = "-USD" in symbol or symbol in ("BTC", "ETH", "SOL", "BNB", "ADA")
    if not is_crypto:
        try:
            fund = await _fundamental_svc.get_fundamentals(symbol)
            if fund:
                fundamentals = fund if isinstance(fund, dict) else fund.dict()
        except Exception as e:
            logger.info(f"[analyse] Fundamentals not available for {symbol}: {e}")

    # ── Layer 5a: Chart Pattern Engine ───────────────────────────────────────
    patterns = None
    try:
        patterns = _pattern_engine.scan(candles or [])
    except Exception as e:
        logger.warning(f"[analyse] Pattern scan failed for {symbol}: {e}")

    # ── Macro overview (FRED) — feeds correlation engine + prompt ────────────
    macro_overview: dict = {}
    try:
        macro_cache_key = "macro:overview"
        macro_overview = cache_manager.get(macro_cache_key) or {}
        if not macro_overview:
            macro_overview = await _fred_svc.get_macro_overview()
            if macro_overview:
                cache_manager.set(macro_cache_key, macro_overview, ttl=3600 * 4)  # 4hr cache
        logger.info(f"[analyse] {symbol} macro fetched: {list(macro_overview.keys())}")
    except Exception as e:
        logger.warning(f"[analyse] Macro fetch failed for {symbol}: {e}")

    # ── Layer 5b: Correlation Engine (news × price + fundamentals + macro) ───
    correlation = _correlation_engine.run(
        news=news,
        quote=quote_dict,
        fundamentals=fundamentals,
        is_crypto=is_crypto,
        macro_overview=macro_overview,
    )

    # ── Layer 6: Claude synthesis ─────────────────────────────────────────────
    analysis_text = _build_fallback_analysis(symbol, signals)
    tokens_used   = 0
    try:
        system_prompt = PromptBuilder.build_analyse_system_prompt()
        user_prompt   = PromptBuilder.build_analyse_user_prompt(
            symbol=symbol,
            interval=interval,
            quote=quote_dict,
            signals=signals,
            prediction=prediction,
            news=news,
            fundamentals=fundamentals,
            correlation=correlation,
            patterns=patterns,
            user_level=user_level,
            macro_overview=macro_overview,
        )
        result = await _claude_svc.generate_analysis(system_prompt, user_prompt)
        analysis_text = result["analysis_text"]
        tokens_used   = result["tokens_used"]
        # Upgrade scenario theses with Claude-generated ones (extracted from tail of response)
        if scenarios:
            scenarios = _apply_claude_theses(scenarios, analysis_text)
    except Exception as e:
        logger.error(f"[analyse] Claude synthesis failed for {symbol}: {e}")

    # ── Phase 2/3: Dean Agent — coaching nudge + lesson id + behaviour event ─
    coaching_nudge: str | None = None
    coaching_lesson_id: str | None = None
    db = _get_db()
    if db and uid:
        ind = signals.indicators
        try:
            coaching_nudge, coaching_lesson_id = await get_coaching_nudge(
                uid=uid,
                symbol=symbol,
                rsi_signal=ind.rsi_signal,
                macd_signal=ind.macd_signal,
                ema_stack=ind.ema_stack,
                db=db,
            )
        except Exception as _e:
            logger.warning(f"[analyse] Dean Agent nudge failed: {_e}")

        # Fire-and-forget: record that this user analysed this symbol
        try:
            scenario_label = (
                scenarios.base.thesis[:40] if scenarios else signals.signal_label.value
            )
            await record_analysis_event(
                uid=uid,
                symbol=symbol,
                signal_label=signals.signal_label.value,
                scenario_label=scenario_label,
                db=db,
            )
        except Exception as _e:
            logger.warning(f"[analyse] Dean Agent event record failed: {_e}")

        # ── Phase 11: Store analysis event in ChromaDB memory ────────────────
        try:
            from app.services.chroma_memory_service import ChromaMemoryService
            _mem = ChromaMemoryService()
            memory_text = (
                f"User analysed {symbol} on {datetime.now(timezone.utc).strftime('%Y-%m-%d')}. "
                f"Signal: {signals.signal_label.value}. "
                f"Composite score: {signals.composite_score:+.2f}. "
                + (f"Base thesis: {scenarios.base.thesis}" if scenarios else "")
            )
            _mem.store(uid, memory_text, category="portfolio", symbol=symbol)
        except Exception as _e:
            logger.debug(f"[analyse] ChromaDB store skipped: {_e}")

    # ── Build response + cache ────────────────────────────────────────────────
    try:
        response = AnalyseResponse(
            symbol=symbol,
            interval=interval,
            signals=signals,
            prediction=prediction,
            correlation=correlation,
            patterns=patterns,
            scenarios=scenarios,
            analysis=analysis_text,
            coaching_nudge=coaching_nudge,
            coaching_lesson_id=coaching_lesson_id,
            timestamp=datetime.now(timezone.utc).isoformat(),
            is_cached=False,
            tokens_used=tokens_used,
        )
        cache_manager.set(cache_key, response.model_dump(mode="json"), ttl=_CACHE_TTL)
        return response
    except Exception as e:
        logger.error(f"[analyse] Failed to build AnalyseResponse for {symbol}: {e}", exc_info=True)
        from fastapi import HTTPException as _HTTPException
        raise _HTTPException(status_code=500, detail=f"Signal engine response build failed: {e}")


def _build_scenarios(signals, prediction) -> "Scenarios | None":
    """Compute bull/base/bear scenario probabilities and price targets from signal score + ATR prediction."""
    if prediction is None:
        return None

    score = signals.composite_score
    if score > 0.3:
        bull_p, base_p, bear_p = 50, 35, 15
    elif score >= 0:
        bull_p, base_p, bear_p = 35, 45, 20
    elif score >= -0.3:
        bull_p, base_p, bear_p = 20, 45, 35
    else:
        bull_p, base_p, bear_p = 15, 35, 50

    cs = signals.candlestick
    pattern_ctx = cs.pattern or "current setup"

    return Scenarios(
        bull=ScenarioCase(
            probability=bull_p,
            price_target=round(prediction.price_target_high, 4),
            thesis=f"Price breaks higher as {pattern_ctx} confirms with expanding volume.",
        ),
        base=ScenarioCase(
            probability=base_p,
            price_target=round(prediction.price_target_base, 4),
            thesis=f"Price consolidates near current level; signal drift toward the {signals.signal_label.value.lower().replace('_', ' ')} case.",
        ),
        bear=ScenarioCase(
            probability=bear_p,
            price_target=round(prediction.price_target_low, 4),
            thesis=f"Support fails and {pattern_ctx} reverses as selling pressure increases.",
        ),
    )


def _apply_claude_theses(scenarios: "Scenarios", analysis_text: str) -> "Scenarios":
    """
    Replace default theses with Claude-generated ones extracted from the
    BULL_THESIS / BASE_THESIS / BEAR_THESIS lines at the end of the analysis.
    Returns the original scenarios unchanged if no theses are found.
    """
    import re
    bull = base = bear = ""
    for line in analysis_text.splitlines():
        line = line.strip()
        m = re.match(r"BULL_THESIS:\s*(.+)", line)
        if m:
            bull = m.group(1).strip()
        m = re.match(r"BASE_THESIS:\s*(.+)", line)
        if m:
            base = m.group(1).strip()
        m = re.match(r"BEAR_THESIS:\s*(.+)", line)
        if m:
            bear = m.group(1).strip()

    if not (bull or base or bear):
        return scenarios  # Claude didn't include theses — keep defaults

    return Scenarios(
        bull=ScenarioCase(
            probability=scenarios.bull.probability,
            price_target=scenarios.bull.price_target,
            thesis=bull or scenarios.bull.thesis,
        ),
        base=ScenarioCase(
            probability=scenarios.base.probability,
            price_target=scenarios.base.price_target,
            thesis=base or scenarios.base.thesis,
        ),
        bear=ScenarioCase(
            probability=scenarios.bear.probability,
            price_target=scenarios.bear.price_target,
            thesis=bear or scenarios.bear.thesis,
        ),
    )


def _build_fallback_analysis(symbol: str, signals) -> str:
    """Plain-text fallback if Claude is unavailable."""
    label = signals.signal_label.value.replace("_", " ")
    score = signals.composite_score
    cs = signals.candlestick
    ind = signals.indicators

    lines = [
        f"{symbol} — Signal Engine result: **{label}** (composite score: {score:+.2f})",
        "",
    ]
    if cs.pattern:
        lines.append(f"Candlestick pattern detected: {cs.pattern} ({cs.signal})")
    lines.append(f"RSI: {ind.rsi_value or 'N/A'} ({ind.rsi_signal})")
    lines.append(f"MACD: {ind.macd_signal}")
    lines.append(f"EMA Stack: {ind.ema_stack}")
    lines.append(f"Volume: {ind.volume}")
    lines.append("")
    lines.append("(AI narrative unavailable — Claude API not configured)")

    return "\n".join(lines)


# ── Phase 9: CrewAI Streaming SSE Endpoint ────────────────────────────────────

@router.get("/analyse/{symbol}/stream")
@limiter.limit("5/minute")
async def analyse_symbol_stream(
    request: Request,
    symbol: str,
    user_level: str = "beginner",
    uid: str = Depends(require_auth),
):
    """
    Server-Sent Events endpoint that streams CrewAI agent progress.

    Flutter listens via Dio's ResponseType.stream and shows each agent's
    status as it completes:
      {"agent": "MarketDataAgent",  "status": "running"}
      {"agent": "SentimentAgent",   "status": "running"}
      {"agent": "TechnicalAgent",   "status": "running"}
      {"agent": "CoachAgent",       "status": "running"}
      {"agent": "done",             "result": {...scenario card...}}

    Falls back gracefully if crewai is not installed.
    """
    sym = symbol.upper()

    async def event_stream():
        agents = [
            ("MarketDataAgent",  "Fetching price, indicators & patterns…"),
            ("SentimentAgent",   "Reading news & macro context…"),
            ("TechnicalAgent",   "Interpreting signals & key levels…"),
            ("CoachAgent",       "Personalising coaching for you…"),
        ]

        # Send agent-start events so the UI can show a progress list
        for name, description in agents:
            yield f"data: {json.dumps({'agent': name, 'status': 'running', 'description': description})}\n\n"
            await asyncio.sleep(0.1)  # small delay so UI renders each chip

        # Run the crew
        try:
            from app.agents.crew import run_crew
            result = await run_crew(symbol=sym, uid=uid, user_level=user_level)

            for name, _ in agents:
                yield f"data: {json.dumps({'agent': name, 'status': 'done'})}\n\n"

            yield f"data: {json.dumps({'agent': 'done', 'result': result})}\n\n"

        except ImportError:
            # CrewAI not installed — fall back to single-agent analysis
            logger.warning("[stream] crewai not installed, sending fallback")
            yield f"data: {json.dumps({'agent': 'done', 'result': {}, 'fallback': True})}\n\n"
        except Exception as e:
            logger.error(f"[stream] crew error for {sym}: {e}")
            yield f"data: {json.dumps({'agent': 'error', 'error': str(e)})}\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control":  "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
