"""
Reddit Sentiment Service — Phase 4.

Scrapes r/wallstreetbets, r/stocks, and r/investing for mentions of a symbol,
scores post titles with VADER, and returns a structured sentiment summary.

Credentials: set REDDIT_CLIENT_ID, REDDIT_CLIENT_SECRET, REDDIT_USER_AGENT
in python-backend/.env (see app/config.py).  Get free keys at:
    https://www.reddit.com/prefs/apps  (create a "script" type application)

When credentials are absent the service returns a graceful degraded response
so the rest of the analysis pipeline is unaffected.
"""

import asyncio
import logging
import re
from datetime import datetime, timezone
from typing import Optional

logger = logging.getLogger(__name__)

# Subreddits to search
_SUBREDDITS = ["wallstreetbets", "stocks", "investing"]

# Maximum posts to fetch per subreddit
_POSTS_PER_SUB = 50

# Maximum top posts to surface in the response
_TOP_POSTS_LIMIT = 5


def _vader_score(text: str) -> float:
    """Return a compound VADER score in [-1, 1] for a given string."""
    try:
        from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
        sia = SentimentIntensityAnalyzer()
        return sia.polarity_scores(text)["compound"]
    except Exception:
        return 0.0


def _symbol_variants(symbol: str) -> list[str]:
    """
    Build a list of case-insensitive patterns to match against post titles.
    E.g. 'AAPL' → ['AAPL', '$AAPL', 'aapl', 'Apple'] (ticker only for now).
    """
    sym = symbol.upper()
    base = sym.replace("-USD", "").replace("-USDT", "")  # strip crypto suffix
    return [base, f"${base}", base.lower(), f"${base.lower()}"]


def _mentions_symbol(title: str, variants: list[str]) -> bool:
    """Return True if any variant appears as a word boundary in the title."""
    for v in variants:
        pattern = rf"(?<![A-Za-z$]){re.escape(v)}(?![A-Za-z])"
        if re.search(pattern, title, re.IGNORECASE):
            return True
    return False


class RedditService:
    """
    Async-friendly Reddit sentiment scraper using PRAW in a thread executor.

    ``is_configured`` is True only when all three credentials are present.
    """

    def __init__(self) -> None:
        from app.config import settings
        self._client_id     = settings.REDDIT_CLIENT_ID
        self._client_secret = settings.REDDIT_CLIENT_SECRET
        self._user_agent    = settings.REDDIT_USER_AGENT

    @property
    def is_configured(self) -> bool:
        return bool(self._client_id and self._client_secret)

    def _build_reddit(self):
        """Build a read-only PRAW Reddit instance."""
        import praw  # imported late so missing praw doesn't break startup
        return praw.Reddit(
            client_id=self._client_id,
            client_secret=self._client_secret,
            user_agent=self._user_agent,
        )

    def _scrape_sync(self, symbol: str) -> dict:
        """
        Synchronous PRAW scrape (runs in a thread via run_in_executor).
        Returns the raw result dict.
        """
        variants = _symbol_variants(symbol)
        reddit   = self._build_reddit()

        matched_posts: list[dict] = []
        mention_count = 0

        for sub_name in _SUBREDDITS:
            try:
                subreddit = reddit.subreddit(sub_name)
                # Hot posts are most relevant for current sentiment
                for post in subreddit.hot(limit=_POSTS_PER_SUB):
                    if _mentions_symbol(post.title, variants):
                        score = _vader_score(post.title)
                        mention_count += 1
                        matched_posts.append({
                            "subreddit":   sub_name,
                            "title":       post.title,
                            "score":       post.score,          # Reddit upvotes
                            "num_comments":post.num_comments,
                            "url":         f"https://reddit.com{post.permalink}",
                            "created_utc": datetime.fromtimestamp(
                                post.created_utc, tz=timezone.utc
                            ).isoformat(),
                            "vader_score": round(score, 4),
                            "sentiment":  (
                                "bullish"  if score >  0.05 else
                                "bearish"  if score < -0.05 else
                                "neutral"
                            ),
                        })
            except Exception as exc:
                logger.warning("RedditService: error fetching r/%s — %s", sub_name, exc)

        if not matched_posts:
            return {
                "symbol":                 symbol,
                "reddit_sentiment_score": 0.0,
                "mention_count":          0,
                "sentiment_label":        "neutral",
                "bullish_count":          0,
                "bearish_count":          0,
                "neutral_count":          0,
                "top_posts":              [],
                "subreddits_searched":    _SUBREDDITS,
                "note":                   "No recent posts found.",
            }

        # Aggregate VADER scores (weight by Reddit upvotes + 1 to avoid 0-weight)
        total_weight = sum(max(p["score"], 1) for p in matched_posts)
        weighted_score = sum(
            p["vader_score"] * max(p["score"], 1) for p in matched_posts
        ) / total_weight

        label = (
            "bullish"  if weighted_score >  0.05 else
            "bearish"  if weighted_score < -0.05 else
            "neutral"
        )

        bullish_count = sum(1 for p in matched_posts if p["sentiment"] == "bullish")
        bearish_count = sum(1 for p in matched_posts if p["sentiment"] == "bearish")
        neutral_count = sum(1 for p in matched_posts if p["sentiment"] == "neutral")

        # Top posts: highest Reddit score first
        top_posts = sorted(matched_posts, key=lambda p: p["score"], reverse=True)
        top_posts = top_posts[:_TOP_POSTS_LIMIT]

        return {
            "symbol":                 symbol,
            "reddit_sentiment_score": round(weighted_score, 4),
            "mention_count":          mention_count,
            "sentiment_label":        label,
            "bullish_count":          bullish_count,
            "bearish_count":          bearish_count,
            "neutral_count":          neutral_count,
            "top_posts":              top_posts,
            "subreddits_searched":    _SUBREDDITS,
        }

    async def get_sentiment(self, symbol: str) -> dict:
        """
        Async entry point — scrapes Reddit in a thread to avoid blocking the
        event loop (PRAW is synchronous).

        Returns a dict with: symbol, reddit_sentiment_score, mention_count,
        sentiment_label, bullish_count, bearish_count, neutral_count, top_posts[].
        On any error returns {"symbol": symbol, "error": "<description>"}.
        """
        if not self.is_configured:
            return {
                "symbol":                 symbol,
                "reddit_sentiment_score": 0.0,
                "mention_count":          0,
                "sentiment_label":        "neutral",
                "bullish_count":          0,
                "bearish_count":          0,
                "neutral_count":          0,
                "top_posts":              [],
                "note": (
                    "Reddit credentials not configured. "
                    "Set REDDIT_CLIENT_ID and REDDIT_CLIENT_SECRET in .env."
                ),
            }

        try:
            loop   = asyncio.get_event_loop()
            result = await loop.run_in_executor(None, self._scrape_sync, symbol.upper())
            return result
        except Exception as exc:
            logger.exception("RedditService.get_sentiment error for %s", symbol)
            return {"symbol": symbol, "error": str(exc)}
