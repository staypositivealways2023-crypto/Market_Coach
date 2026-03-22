"""News Service — financial news per ticker via Massive API + VADER sentiment"""

import aiohttp
from typing import List, Optional
from datetime import datetime
import logging

from app.config import settings

logger = logging.getLogger(__name__)

BASE_URL = "https://api.massive.com"


class NewsArticle:
    def __init__(
        self,
        id: str,
        title: str,
        description: Optional[str],
        url: str,
        source: str,
        published_at: str,
        tickers: List[str],
        sentiment_score: float,   # -1.0 (bearish) to +1.0 (bullish)
        sentiment_label: str,     # positive | negative | neutral
    ):
        self.id = id
        self.title = title
        self.description = description
        self.url = url
        self.source = source
        self.published_at = published_at
        self.tickers = tickers
        self.sentiment_score = sentiment_score
        self.sentiment_label = sentiment_label

    def to_dict(self):
        return self.__dict__


class NewsService:
    """Fetches financial news from Massive API with sentiment scoring"""

    def __init__(self):
        self.api_key = settings.MASSIVE_API_KEY
        self._vader = None  # lazy load

    @property
    def is_configured(self) -> bool:
        return bool(self.api_key)

    def _get_vader(self):
        if self._vader is None:
            try:
                from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
                self._vader = SentimentIntensityAnalyzer()
            except ImportError:
                logger.warning("vaderSentiment not installed — sentiment scoring disabled")
                self._vader = False
        return self._vader if self._vader is not False else None

    def _score_sentiment(self, text: str) -> tuple[float, str]:
        """Returns (compound_score, label). Score: -1 to +1"""
        vader = self._get_vader()
        if not vader or not text:
            return 0.0, "neutral"

        scores = vader.polarity_scores(text)
        compound = scores["compound"]

        if compound >= 0.05:
            label = "positive"
        elif compound <= -0.05:
            label = "negative"
        else:
            label = "neutral"

        return round(compound, 3), label

    async def get_news(self, symbol: str, limit: int = 20) -> List[NewsArticle]:
        """Fetch latest news for a ticker symbol"""
        if not self.is_configured:
            logger.warning("Massive API not configured — news unavailable")
            return []

        try:
            url = f"{BASE_URL}/v2/reference/news"
            params = {
                "ticker": symbol.upper(),
                "limit": limit,
                "sort": "published_utc",
                "order": "desc",
                "apiKey": self.api_key,
            }

            async with aiohttp.ClientSession() as session:
                async with session.get(url, params=params) as resp:
                    if resp.status != 200:
                        logger.warning(f"Massive news {symbol}: HTTP {resp.status}")
                        return []
                    data = await resp.json()

            articles = []
            for item in data.get("results", []):
                title = item.get("title", "")
                description = item.get("description") or item.get("article_url", "")

                # Score on title + description combined for better accuracy
                text_to_score = f"{title}. {description}"
                score, label = self._score_sentiment(text_to_score)

                articles.append(NewsArticle(
                    id=item.get("id", ""),
                    title=title,
                    description=item.get("description"),
                    url=item.get("article_url", ""),
                    source=item.get("publisher", {}).get("name", "Unknown"),
                    published_at=item.get("published_utc", ""),
                    tickers=item.get("tickers", []),
                    sentiment_score=score,
                    sentiment_label=label,
                ))

            logger.info(f"Fetched {len(articles)} news articles for {symbol}")
            return articles

        except Exception as e:
            logger.error(f"News fetch error for {symbol}: {e}")
            return []

    async def get_market_news(self, limit: int = 30) -> List[NewsArticle]:
        """General market news (no ticker filter)"""
        if not self.is_configured:
            return []

        try:
            url = f"{BASE_URL}/v2/reference/news"
            params = {
                "limit": limit,
                "sort": "published_utc",
                "order": "desc",
                "apiKey": self.api_key,
            }

            async with aiohttp.ClientSession() as session:
                async with session.get(url, params=params) as resp:
                    if resp.status != 200:
                        return []
                    data = await resp.json()

            articles = []
            for item in data.get("results", []):
                title = item.get("title", "")
                score, label = self._score_sentiment(title)
                articles.append(NewsArticle(
                    id=item.get("id", ""),
                    title=title,
                    description=item.get("description"),
                    url=item.get("article_url", ""),
                    source=item.get("publisher", {}).get("name", "Unknown"),
                    published_at=item.get("published_utc", ""),
                    tickers=item.get("tickers", []),
                    sentiment_score=score,
                    sentiment_label=label,
                ))

            return articles

        except Exception as e:
            logger.error(f"Market news error: {e}")
            return []
