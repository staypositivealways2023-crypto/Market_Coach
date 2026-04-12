"""Analysis Router - AI-powered market analysis endpoints"""

from fastapi import APIRouter, Depends, HTTPException, status, Request
from datetime import datetime
from typing import Optional
import logging

from pydantic import BaseModel

from app.models.analysis import AIAnalysisResponse
from app.services.analysis_aggregator import AnalysisAggregator
from app.services.claude_service import ClaudeService
from app.services.mock_analysis_service import MockAnalysisService
from app.services.structured_analysis_service import StructuredAnalysisService
from app.utils.prompt_builder import PromptBuilder
from app.utils.cache import cache_manager
from app.utils.analysis_rate_limiter import analysis_rate_limiter
from app.utils.auth import require_auth
from app.utils.rate_limit import limiter
from app.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()

# Initialize services
aggregator = AnalysisAggregator()
claude_service = ClaudeService()
mock_service = MockAnalysisService()
prompt_builder = PromptBuilder()
structured_service = StructuredAnalysisService()

# Cache TTL: 5 minutes
ANALYSIS_CACHE_TTL = 300


@router.post("/analyze/{symbol}", response_model=AIAnalysisResponse)
async def analyze_symbol(symbol: str, request: Request):
    """
    Generate AI-powered market analysis for a symbol

    Args:
        symbol: Stock ticker (e.g., 'AAPL', 'BTC-USD', 'TSLA')
        request: FastAPI request object (for IP tracking)

    Returns:
        AIAnalysisResponse with markdown analysis

    Raises:
        400: Invalid symbol or insufficient data
        429: Rate limit exceeded
        500: Internal server error
        503: Claude API unavailable
    """

    # Normalize symbol
    symbol = symbol.upper()

    # Get user identifier (IP address for now, will use user ID when auth implemented)
    user_id = request.client.host if request.client else "unknown"

    logger.info(f"Analysis request for {symbol} from {user_id}")

    # Check rate limit BEFORE checking cache
    # TODO: Replace with actual auth check when implemented
    is_authenticated = False  # For now, all users are guests

    can_proceed, remaining = analysis_rate_limiter.can_proceed(
        user_id=user_id,
        is_authenticated=is_authenticated
    )

    if not can_proceed:
        logger.warning(f"Rate limit exceeded for {user_id}")
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                "Daily analysis limit reached. "
                f"{'Authenticate to get more requests' if not is_authenticated else 'Try again tomorrow'}."
            ),
            headers={"X-RateLimit-Remaining": "0"}
        )

    # Check cache first (after rate limit check)
    cache_key = f"ai_analysis:{symbol}"
    cached = cache_manager.get(cache_key)

    if cached:
        logger.info(f"Analysis cache hit for {symbol} (user: {user_id})")

        # Add rate limit headers
        response = AIAnalysisResponse(
            symbol=symbol,
            analysis_text=cached["analysis_text"],
            timestamp=datetime.fromisoformat(cached["timestamp"]),
            is_cached=True,
            tokens_used=cached.get("tokens_used")
        )

        # Note: Can't set headers directly on Pydantic model
        # Consider using Response object if headers needed
        return response

    # Cache miss - generate new analysis
    try:
        # Check if we should use mock service
        use_mock = settings.USE_MOCK_ANALYSIS or not settings.ANTHROPIC_API_KEY

        if use_mock:
            # Use mock analysis (no API calls, instant response)
            logger.info(f"Using MOCK analysis for {symbol}")
            result = mock_service.generate_mock_analysis(symbol)
            analysis_text = result["analysis_text"]
            tokens_used = result["tokens_used"]

        else:
            # Use real Claude API
            # 1. Aggregate market data
            logger.info(f"Aggregating market data for {symbol}")
            context = await aggregator.aggregate_market_data(symbol)

            if not context:
                logger.error(f"Failed to aggregate data for {symbol}")
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Could not fetch market data for {symbol}. Check if symbol is valid."
                )

            # 2. Build prompts
            system_prompt = prompt_builder.build_system_prompt()
            user_prompt = prompt_builder.build_user_prompt(context)

            logger.debug(f"User prompt length: {len(user_prompt)} chars")

            # 3. Call Claude API
            try:
                result = await claude_service.generate_analysis(
                    system_prompt=system_prompt,
                    user_prompt=user_prompt
                )

                analysis_text = result["analysis_text"]
                tokens_used = result["tokens_used"]

                logger.info(f"Successfully generated analysis for {symbol} ({tokens_used} tokens)")

            except ValueError as e:
                logger.error(f"Claude API key not configured: {e}")
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="AI analysis service is not configured. Please contact administrator."
                )

            except Exception as e:
                # Handle rate limits
                if "rate_limit" in str(e).lower() or "429" in str(e):
                    logger.warning(f"Rate limit hit for {symbol}")
                    raise HTTPException(
                        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                        detail="AI analysis rate limit exceeded. Please try again in a few minutes."
                    )

                logger.error(f"Claude API error for {symbol}: {e}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=f"Failed to generate analysis: {str(e)}"
                )

        # 4. Cache result
        timestamp = datetime.utcnow()

        cache_data = {
            "analysis_text": analysis_text,
            "timestamp": timestamp.isoformat(),
            "tokens_used": tokens_used
        }

        cache_manager.set(cache_key, cache_data, ttl=ANALYSIS_CACHE_TTL)

        # 5. Return response
        return AIAnalysisResponse(
            symbol=symbol,
            analysis_text=analysis_text,
            timestamp=timestamp,
            is_cached=False,
            tokens_used=tokens_used
        )

    except HTTPException:
        # Re-raise HTTP exceptions
        raise

    except Exception as e:
        logger.error(f"Unexpected error analyzing {symbol}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred. Please try again later."
        )


@router.get("/structured/{symbol}")
async def get_structured_analysis(symbol: str):
    """
    Structured JSON analysis — same schema as Flutter EnhancedAIAnalysis.
    Used by Flutter when no direct Anthropic key is configured.
    Cached 6 hours.
    """
    sym = symbol.upper()
    cache_key = f"structured_analysis:{sym}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    if not structured_service.is_configured:
        raise HTTPException(status_code=503, detail="AI analysis not configured on server.")

    try:
        result = await structured_service.analyze(sym)
        cache_manager.set(cache_key, result, ttl=21600)  # 6 hr
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Structured analysis error for {sym}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Analysis failed: {e}")


class TradeDebriefRequest(BaseModel):
    symbol: str
    action: str  # BUY | SELL
    shares: float
    price: float
    composite_score: Optional[float] = None
    trend: Optional[str] = None
    rsi_value: Optional[float] = None
    rsi_signal: Optional[str] = None   # OVERSOLD | NEUTRAL | OVERBOUGHT
    macd_signal: Optional[str] = None  # BULLISH | BEARISH | BULLISH_CROSS | BEARISH_CROSS
    pattern_name: Optional[str] = None # e.g. DOJI, HAMMER, ENGULFING
    ema_stack: Optional[str] = None    # PRICE_ABOVE_ALL | MIXED | PRICE_BELOW_ALL etc.


@router.post("/trade-debrief")
@limiter.limit("20/minute")
async def trade_debrief(request: Request, req: TradeDebriefRequest, uid: str = Depends(require_auth)):
    """
    Generate a 3-sentence AI debrief for a completed paper trade.
    Keeps the Claude API key server-side — never exposed to the Flutter binary.
    """
    if not settings.ANTHROPIC_API_KEY:
        raise HTTPException(status_code=503, detail="AI service not configured on server.")

    # Build indicator context string from available fields
    ctx_parts = []
    if req.composite_score is not None:
        ctx_parts.append(f"composite score {req.composite_score:.1f}/100")
    if req.trend:
        ctx_parts.append(f"candlestick trend {req.trend}")
    if req.pattern_name:
        ctx_parts.append(f"pattern: {req.pattern_name}")
    if req.rsi_value is not None and req.rsi_signal:
        ctx_parts.append(f"RSI {req.rsi_value:.1f} ({req.rsi_signal})")
    elif req.rsi_signal:
        ctx_parts.append(f"RSI signal: {req.rsi_signal}")
    if req.macd_signal:
        ctx_parts.append(f"MACD: {req.macd_signal}")
    if req.ema_stack:
        ctx_parts.append(f"EMA stack: {req.ema_stack}")

    indicator_ctx = (
        f"Signal context at trade time — {', '.join(ctx_parts)}."
        if ctx_parts else ""
    )

    prompt = (
        f"In 3 sentences max, explain whether market signals supported or "
        f"contradicted this {req.action} of {req.shares:.4f} "
        f"{req.symbol.upper()} at ${req.price:.2f}. "
        f"{indicator_ctx} Include sentiment and momentum context."
    )

    try:
        result = await claude_service.generate_analysis(
            system_prompt="You are a concise trading coach. Reply in plain prose, no markdown.",
            user_prompt=prompt,
            max_tokens=200,
        )
        return {"text": result["analysis_text"]}
    except Exception as e:
        logger.error(f"Trade debrief error for {req.symbol}: {e}")
        raise HTTPException(status_code=500, detail="Debrief generation failed.")


@router.delete("/analyze/{symbol}/cache")
async def clear_analysis_cache(symbol: str):
    """
    Clear cached analysis for a symbol

    Args:
        symbol: Stock ticker

    Returns:
        Success message
    """

    symbol = symbol.upper()
    cache_key = f"ai_analysis:{symbol}"

    cache_manager.delete(cache_key)

    logger.info(f"Cleared analysis cache for {symbol}")

    return {
        "message": f"Cache cleared for {symbol}",
        "symbol": symbol
    }
