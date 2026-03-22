"""News endpoints — financial news per ticker with sentiment"""

from fastapi import APIRouter, HTTPException, Query
import logging

from app.services.news_service import NewsService
from app.utils.cache import cache_manager

logger = logging.getLogger(__name__)
router = APIRouter()

news_svc = NewsService()


@router.get("/ticker/{symbol}")
async def get_ticker_news(
    symbol: str,
    limit: int = Query(20, ge=1, le=50),
):
    """Latest news + sentiment for a ticker"""
    cache_key = f"news:{symbol.upper()}:{limit}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    articles = await news_svc.get_news(symbol.upper(), limit=limit)

    if not articles:
        raise HTTPException(status_code=404, detail=f"No news found for {symbol}")

    # Aggregate sentiment summary
    scores = [a.sentiment_score for a in articles]
    avg_score = round(sum(scores) / len(scores), 3) if scores else 0.0
    positive = sum(1 for a in articles if a.sentiment_label == "positive")
    negative = sum(1 for a in articles if a.sentiment_label == "negative")
    neutral = len(articles) - positive - negative

    result = {
        "symbol": symbol.upper(),
        "article_count": len(articles),
        "sentiment_summary": {
            "average_score": avg_score,
            "overall": "positive" if avg_score > 0.05 else "negative" if avg_score < -0.05 else "neutral",
            "positive_count": positive,
            "negative_count": negative,
            "neutral_count": neutral,
        },
        "articles": [a.to_dict() for a in articles],
    }

    cache_manager.set(cache_key, result, ttl=900)  # 15 min cache
    return result


@router.get("/market")
async def get_market_news(
    limit: int = Query(30, ge=1, le=50),
):
    """General market news feed"""
    cache_key = f"news:market:{limit}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    articles = await news_svc.get_market_news(limit=limit)

    if not articles:
        raise HTTPException(status_code=503, detail="News unavailable")

    result = {
        "article_count": len(articles),
        "articles": [a.to_dict() for a in articles],
    }
    cache_manager.set(cache_key, result, ttl=900)
    return result
