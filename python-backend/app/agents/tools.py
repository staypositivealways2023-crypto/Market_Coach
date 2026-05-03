"""
CrewAI Tool wrappers -- thin async-to-sync bridges around existing services.

Phase 3 additions:
  get_deep_fundamentals   -- DCF intrinsic value, quality scoring (FundamentalsAgent)
  calculate_risk_metrics  -- ATR position sizing, stop/take-profit (RiskAgent)
  get_finbert_sentiment   -- Explicit FinBERT article-level scores (SentimentAgent)
"""

import asyncio
import json
import logging
from typing import Optional

import numpy as np
from crewai.tools import tool

logger = logging.getLogger(__name__)


def _run(coro):
    """Run an async coroutine synchronously (thread-safe)."""
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
                fut = ex.submit(asyncio.run, coro)
                return fut.result(timeout=30)
        return loop.run_until_complete(coro)
    except Exception:
        return asyncio.run(coro)


@tool("get_market_data")
def get_market_data(symbol: str) -> str:
    """
    Fetch real-time quote, 90-day daily candles, and technical indicators
    (RSI, MACD, EMA stack, Bollinger Bands, ATR) for a stock or crypto symbol.
    Returns a JSON string with: price, change_percent, rsi, macd_histogram,
    ema_stack, volume, atr, candle_count.
    """
    from app.services.data_fetcher import MarketDataFetcher
    from app.services.indicator_service import TechnicalIndicatorService

    sym = symbol.strip().upper()
    fetcher   = MarketDataFetcher()
    indicator = TechnicalIndicatorService()

    async def _fetch():
        quote, candles = await asyncio.gather(
            fetcher.get_quote(sym),
            fetcher.get_candles(sym, interval="1d", limit=90),
            return_exceptions=True,
        )
        return quote, candles

    quote, candles = _run(_fetch())

    indicators = {}
    if isinstance(candles, list) and candles:
        try:
            indicators = indicator.calculate_all(candles)
        except Exception as e:
            logger.warning(f"[tools] indicator calc failed for {sym}: {e}")

    result = {
        "symbol":         sym,
        "price":          quote.price          if hasattr(quote, "price") else None,
        "change_percent": quote.change_percent  if hasattr(quote, "change_percent") else None,
        "volume":         quote.volume          if hasattr(quote, "volume") else None,
        "market_cap":     quote.market_cap      if hasattr(quote, "market_cap") else None,
        "candle_count":   len(candles) if isinstance(candles, list) else 0,
        **indicators,
    }
    return json.dumps(result, default=str)


@tool("detect_chart_patterns")
def detect_chart_patterns(symbol: str) -> str:
    """
    Run pattern recognition on the last 90 daily candles for a symbol.
    Returns: list of detected patterns (e.g. double_top, head_and_shoulders,
    support_bounce) with their signal direction and confidence score.
    """
    from app.services.data_fetcher import MarketDataFetcher
    from app.services.pattern_engine import PatternEngine

    sym     = symbol.strip().upper()
    fetcher = MarketDataFetcher()
    engine  = PatternEngine()

    candles = _run(fetcher.get_candles(sym, interval="1d", limit=90))

    if not candles:
        return json.dumps({"symbol": sym, "patterns": [], "error": "no candle data"})

    try:
        patterns = engine.scan(candles)
        return json.dumps({
            "symbol":   sym,
            "patterns": [p.dict() if hasattr(p, "dict") else str(p) for p in (patterns or [])],
        }, default=str)
    except Exception as e:
        return json.dumps({"symbol": sym, "patterns": [], "error": str(e)})


@tool("get_news_sentiment")
def get_news_sentiment(symbol: str) -> str:
    """
    Fetch the latest 20 news articles for a symbol and score their sentiment
    using FinBERT (if available) or VADER. Returns: article headlines,
    average sentiment score (-1 to +1), overall label (positive/negative/neutral).
    """
    from app.services.news_service import NewsService

    sym      = symbol.strip().upper()
    svc      = NewsService()
    articles = _run(svc.get_news(sym, limit=20))

    if not articles:
        return json.dumps({"symbol": sym, "article_count": 0,
                           "average_sentiment": 0.0, "overall": "neutral", "headlines": []})

    scores    = [a.sentiment_score for a in articles]
    avg       = round(sum(scores) / len(scores), 3)
    overall   = "positive" if avg > 0.05 else "negative" if avg < -0.05 else "neutral"
    headlines = [{"title": a.title, "source": a.source, "sentiment": a.sentiment_label}
                 for a in articles[:10]]

    return json.dumps({"symbol": sym, "article_count": len(articles),
                       "average_sentiment": avg, "overall": overall,
                       "headlines": headlines}, default=str)


@tool("get_macro_context")
def get_macro_context(dummy: str = "US") -> str:
    """
    Fetch macro-economic context: US Fed funds rate, CPI, 10Y yield,
    dollar index (DXY), and Fear and Greed Index.
    Pass any string (e.g. "US") -- the argument is not used.
    """
    from app.services.fred_service import FredService

    svc  = FredService()
    data = _run(svc.get_overview()) if hasattr(svc, "get_overview") else {}

    return json.dumps({
        "source": "FRED + market data",
        "macro":  data if data else {
            "note": "FRED not configured -- set FRED_API_KEY in .env for live macro data",
        },
    }, default=str)


@tool("get_fundamentals")
def get_fundamentals(symbol: str) -> str:
    """
    Fetch fundamental data for a stock: P/E ratio, revenue growth, EPS,
    profit margin, debt/equity, and analyst price target.
    Not applicable to crypto -- returns empty for crypto symbols.
    """
    from app.services.fundamental_service import FundamentalService
    from app.services.data_fetcher import _is_crypto_symbol

    sym = symbol.strip().upper()
    if _is_crypto_symbol(sym):
        return json.dumps({"symbol": sym, "note": "fundamentals not available for crypto"})

    svc  = FundamentalService()
    data = _run(svc.get_fundamentals(sym))

    if data is None:
        return json.dumps({"symbol": sym, "error": "fundamentals unavailable"})

    return json.dumps(data.dict() if hasattr(data, "dict") else data, default=str)


# Phase 3: Deep Fundamentals Tool (FundamentalsAgent)

@tool("get_deep_fundamentals")
def get_deep_fundamentals(symbol: str) -> str:
    """
    Deep fundamental value analysis: DCF intrinsic value, WACC, margin of safety,
    earnings quality score (0-100), balance sheet health, revenue/EPS growth trends,
    and analyst consensus. Not applicable to crypto.
    """
    from app.services.fundamental_service import FundamentalService
    from app.services.valuation_service import ValuationService
    from app.services.data_fetcher import _is_crypto_symbol

    sym = symbol.strip().upper()
    if _is_crypto_symbol(sym):
        return json.dumps({"symbol": sym, "note": "fundamentals not available for crypto"})

    fund_svc = FundamentalService()
    val_svc  = ValuationService()

    async def _fetch():
        return await asyncio.gather(
            fund_svc.get_fundamentals(sym),
            val_svc.calculate_dcf(sym),
            return_exceptions=True,
        )

    fundamentals, dcf = _run(_fetch())
    result: dict = {"symbol": sym}

    if not isinstance(fundamentals, Exception) and fundamentals:
        f = (fundamentals.dict() if hasattr(fundamentals, "dict")
             else (fundamentals if isinstance(fundamentals, dict) else {}))
        result.update({
            "pe_ratio": f.get("pe_ratio"), "pb_ratio": f.get("pb_ratio"),
            "ev_ebitda": f.get("ev_ebitda"), "profit_margin": f.get("profit_margin"),
            "roe": f.get("roe"), "debt_to_equity": f.get("debt_to_equity"),
            "revenue_growth": f.get("revenue_growth"), "eps_growth": f.get("eps_growth"),
            "analyst_target": f.get("analyst_target"), "analyst_rating": f.get("analyst_rating"),
        })

    if not isinstance(dcf, Exception) and dcf:
        d = dcf.dict() if hasattr(dcf, "dict") else (dcf if isinstance(dcf, dict) else {})
        result.update({
            "dcf_fair_value": d.get("intrinsic_value"),
            "margin_of_safety": d.get("upside_percent"),
            "wacc": d.get("wacc"),
            "growth_rate_used": d.get("growth_rate"),
            "dcf_signal": d.get("signal"),
            "dcf_confidence": d.get("confidence"),
        })

    result["quality_score"] = _compute_quality_score(result)
    result["quality_label"] = (
        "high"   if result["quality_score"] >= 70 else
        "medium" if result["quality_score"] >= 40 else "low"
    )
    return json.dumps(result, default=str)


def _compute_quality_score(data: dict) -> int:
    """Rule-based earnings quality score (0-100)."""
    score = 50
    pm  = data.get("profit_margin")
    roe = data.get("roe")
    de  = data.get("debt_to_equity")
    rg  = data.get("revenue_growth")
    eg  = data.get("eps_growth")
    mos = data.get("margin_of_safety")
    if pm  is not None: score += 10 if pm  > 0.15 else (-10 if pm  < 0    else 0)
    if roe is not None: score += 10 if roe > 0.15 else (-5  if roe < 0    else 0)
    if de  is not None: score += 10 if de  < 0.5  else (-15 if de  > 2.5  else 0)
    if rg  is not None: score += 10 if rg  > 0.10 else (-5  if rg  < 0    else 0)
    if eg  is not None: score += 10 if eg  > 0.15 else (-5  if eg  < 0    else 0)
    if mos is not None: score += 10 if mos > 20   else (-10 if mos < -20  else 0)
    return max(0, min(100, score))


# Phase 3: Risk Metrics Tool (RiskAgent)

@tool("calculate_risk_metrics")
def calculate_risk_metrics(symbol: str) -> str:
    """
    Quantitative risk assessment: ATR-based stop-loss (1.5x ATR), take-profit
    (2.5x ATR), risk/reward ratio, suggested position size using the 2%-per-trade
    rule, composite signal score, and risk level (low/medium/high/very_high).
    """
    from app.services.data_fetcher import MarketDataFetcher
    from app.services.indicator_service import TechnicalIndicatorService
    from app.services.signal_engine import SignalEngine
    from app.services.prediction_engine import PredictionEngine

    sym      = symbol.strip().upper()
    fetcher  = MarketDataFetcher()
    ind_svc  = TechnicalIndicatorService()
    sig_eng  = SignalEngine()
    pred_eng = PredictionEngine()

    async def _fetch():
        return await asyncio.gather(
            fetcher.get_quote(sym),
            fetcher.get_candles(sym, interval="1d", limit=90),
            return_exceptions=True,
        )

    quote, candles = _run(_fetch())

    if isinstance(candles, Exception) or not candles:
        return json.dumps({"symbol": sym, "error": "no candle data for risk calculation"})

    try:
        indicators = ind_svc.calculate_all(candles)
        signals    = sig_eng.run(candles, None)
    except Exception as e:
        return json.dumps({"symbol": sym, "error": f"signal calc failed: {e}"})

    price = (quote.price
             if (not isinstance(quote, Exception) and hasattr(quote, "price")) else None)
    atr   = (indicators.get("atr") if isinstance(indicators, dict)
             else getattr(indicators, "atr", None))

    result: dict = {"symbol": sym, "current_price": price, "atr_14": atr}

    if price and atr and atr > 0:
        stop_loss        = round(price - 1.5 * atr, 2)
        take_profit      = round(price + 2.5 * atr, 2)
        risk_per_share   = price - stop_loss
        reward_per_share = take_profit - price
        atr_pct          = (atr / price) * 100
        result.update({
            "stop_loss":                   stop_loss,
            "take_profit":                 take_profit,
            "risk_reward_ratio":           round(reward_per_share / risk_per_share, 2),
            "suggested_position_size_pct": round((0.02 * price) / risk_per_share * 100, 1),
            "atr_pct":                     round(atr_pct, 2),
            "risk_level": (
                "very_high" if atr_pct > 4.0 else
                "high"      if atr_pct > 2.5 else
                "medium"    if atr_pct > 1.5 else "low"
            ),
        })

    if not isinstance(signals, Exception):
        result["composite_score"] = getattr(signals, "composite_score", None)
        sl = getattr(signals, "signal_label", None)
        result["signal_label"] = sl.value if hasattr(sl, "value") else str(sl) if sl else None

    try:
        predictions = pred_eng.calculate(candles, signals, interval="1d")
        if predictions and not isinstance(predictions, Exception):
            p = predictions.dict() if hasattr(predictions, "dict") else predictions
            result.update({
                "predicted_target": p.get("target"),
                "predicted_high":   p.get("high"),
                "predicted_low":    p.get("low"),
                "horizon":          p.get("horizon"),
            })
    except Exception:
        pass

    # ── Phase 9: Tail-Risk / Black Swan metrics (1yr daily candles) ──────────
    try:
        candles_1yr = _run(fetcher.get_candles(sym, interval="1d", limit=252))
        closes  = np.array([c.close for c in candles_1yr])
        returns = np.diff(np.log(closes))

        var_95  = round(float(np.percentile(returns, 5)), 4)
        cvar_95 = round(float(returns[returns <= np.percentile(returns, 5)].mean()), 4)
        var_99  = round(float(np.percentile(returns, 1)), 4)

        cum             = np.cumprod(1 + returns)
        dd              = (cum / np.maximum.accumulate(cum)) - 1
        max_drawdown_1yr = round(float(dd.min()), 4)

        excess_kurtosis  = round(
            float(((returns - returns.mean()) ** 4).mean() / returns.std() ** 4 - 3), 2
        )
        black_swan_prone = bool(excess_kurtosis > 3)

        black_swan_scenarios = [
            {
                "event": "-3σ move",
                "probability": round(0.0013 * 252, 4),
                "price_impact_pct": round(float(-3 * returns.std() * 100), 2),
            },
            {
                "event": "-5σ move",
                "probability": round(0.0000003 * 252, 6),
                "price_impact_pct": round(float(-5 * returns.std() * 100), 2),
            },
        ]

        result.update({
            "var_95":                var_95,
            "cvar_95":               cvar_95,
            "var_99":                var_99,
            "max_drawdown_1yr":      max_drawdown_1yr,
            "excess_kurtosis":       excess_kurtosis,
            "black_swan_prone":      black_swan_prone,
            "black_swan_scenarios":  black_swan_scenarios,
        })
    except Exception as e:
        logger.warning(f"[tools] tail-risk calc failed for {sym}: {e}")
        result.update({
            "var_95":               None,
            "cvar_95":              None,
            "var_99":               None,
            "max_drawdown_1yr":     None,
            "excess_kurtosis":      None,
            "black_swan_prone":     False,
            "black_swan_scenarios": None,
        })

    return json.dumps(result, default=str)


# Phase 3: FinBERT Sentiment Tool (SentimentAgent)

@tool("get_finbert_sentiment")
def get_finbert_sentiment(symbol: str) -> str:
    """
    Score news articles using FinBERT (ProsusAI/finbert), a BERT model fine-tuned
    on financial text. Returns per-article scores, aggregate distribution
    (positive/negative/neutral counts), sentiment momentum (improving/stable/
    worsening), and the most bullish and bearish headlines.
    Falls back to VADER if FinBERT is unavailable.
    """
    from app.services.news_service import NewsService
    from app.services.finbert_service import FinBERTService

    sym      = symbol.strip().upper()
    news_svc = NewsService()
    finbert  = FinBERTService()
    articles = _run(news_svc.get_news(sym, limit=20))

    if not articles:
        return json.dumps({
            "symbol": sym, "article_count": 0, "finbert_available": False,
            "overall": "neutral", "average_score": 0.0,
            "distribution": {"positive": 0, "negative": 0, "neutral": 0},
        })

    headlines     = [a.title for a in articles]
    finbert_avail = False
    scored        = []

    try:
        batch = finbert.score_batch(headlines)
        finbert_avail = any(s != 0.0 for s, _ in batch)
        for i, (fb_score, fb_label) in enumerate(batch):
            a = articles[i]
            scored.append({"title": a.title, "source": a.source,
                           "score": fb_score, "label": fb_label})
    except Exception:
        for a in articles:
            scored.append({"title": a.title, "source": a.source,
                           "score": a.sentiment_score, "label": a.sentiment_label})

    all_scores = [s["score"] for s in scored]
    avg_score  = round(sum(all_scores) / len(all_scores), 3) if all_scores else 0.0
    overall    = "positive" if avg_score > 0.05 else "negative" if avg_score < -0.05 else "neutral"
    distribution = {
        "positive": sum(1 for s in scored if s["label"] == "positive"),
        "negative": sum(1 for s in scored if s["label"] == "negative"),
        "neutral":  sum(1 for s in scored if s["label"] == "neutral"),
    }
    mid        = max(len(all_scores) // 2, 1)
    avg_recent = sum(all_scores[:mid]) / mid
    avg_older  = (sum(all_scores[mid:]) / (len(all_scores) - mid)
                  if len(all_scores) > mid else avg_recent)
    momentum   = ("improving" if avg_recent > avg_older + 0.05 else
                  "worsening" if avg_recent < avg_older - 0.05 else "stable")
    by_score   = sorted(scored, key=lambda x: x["score"], reverse=True)

    return json.dumps({
        "symbol": sym, "finbert_available": finbert_avail,
        "article_count": len(scored), "average_score": avg_score,
        "overall": overall, "distribution": distribution, "momentum": momentum,
        "most_bullish_headline": by_score[0]["title"]  if by_score else None,
        "most_bearish_headline": by_score[-1]["title"] if by_score else None,
        "articles": scored[:15],
    }, default=str)


# User Memory Tool

@tool("recall_user_context")
def recall_user_context(query: str) -> str:
    """
    Recall relevant memories for the current user from ChromaDB.
    Pass a natural-language query such as "what symbols has this user been watching"
    or "user risk tolerance". Returns up to 5 semantically relevant memory snippets.
    """
    from app.agents.crew import _CURRENT_UID

    uid = _CURRENT_UID or "anonymous"
    try:
        from app.services.chroma_memory_service import ChromaMemoryService
        svc      = ChromaMemoryService()
        memories = svc.recall(uid, query=query, n=5)
        return json.dumps({"uid": uid, "memories": memories})
    except Exception as e:
        return json.dumps({"uid": uid, "memories": [], "error": str(e)})
