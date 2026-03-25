"""
/api/analyse  — Phase 3+4 Signal Engine + Probability Engine endpoint.

Orchestrates all 5 intelligence layers:
  1. Data Ingestion      → candles + quote
  2. Signal Engine       → composite_score + signal_label
  3. Probability Engine  → ATR price range, risk/reward, stop-loss  [Phase 4]
  4. News sentiment      → sentiment score + headlines
  5. Fundamentals        → P/E, revenue growth (stocks only)
  6. Claude synthesis    → plain-English narrative
"""

from datetime import datetime, timezone
from fastapi import APIRouter
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
from app.utils.prompt_builder import PromptBuilder
from app.utils.cache import cache_manager
from app.models.signals import AnalyseResponse

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
async def analyse_symbol(
    symbol: str,
    interval: str = "1d",
    user_level: str = "beginner",
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
    except Exception as e:
        logger.error(f"[analyse] Claude synthesis failed for {symbol}: {e}")

    # ── Build response + cache ────────────────────────────────────────────────
    try:
        response = AnalyseResponse(
            symbol=symbol,
            interval=interval,
            signals=signals,
            prediction=prediction,
            correlation=correlation,
            patterns=patterns,
            analysis=analysis_text,
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
