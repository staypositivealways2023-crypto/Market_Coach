"""Earnings endpoints — historical EPS + upcoming earnings date + calendar + AI prediction"""

import asyncio
from datetime import datetime, date, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
import logging

from app.services.earnings_service import EarningsService
from app.services.claude_service import ClaudeService
from app.utils.cache import cache_manager
from app.config import settings

logger = logging.getLogger(__name__)
router = APIRouter()

earnings_svc = EarningsService()
claude_svc   = ClaudeService()

# Universe for the earnings calendar  (stocks only — crypto has no earnings)
_CALENDAR_UNIVERSE = [
    "AAPL","MSFT","NVDA","GOOGL","AMZN","META","TSLA","BRK-B",
    "JPM","V","JNJ","UNH","XOM","PG","MA","HD","CVX","MRK",
    "ABBV","LLY","AVGO","COST","PEP","KO","TMO","WMT","BAC",
    "DIS","CSCO","ADBE","ACN","CRM","NFLX","INTC","AMD","QCOM",
    "GS","MS","PFE","RIVN","PLTR",
]


# ── Single-symbol earnings ────────────────────────────────────────────────────

@router.get("/calendar")
async def get_earnings_calendar(
    days_ahead: int = Query(30, ge=1, le=90, description="How many days ahead to look"),
):
    """
    Upcoming earnings dates for a curated universe of stocks.
    Results are grouped by date and sorted chronologically.
    Cached 6 hours.
    """
    cache_key = f"earnings_calendar:{days_ahead}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    # Fetch upcoming earnings for all symbols in parallel (yfinance calendar).
    # Each symbol gets a 6s timeout so one slow ticker can't block the whole response.
    async def _safe_upcoming(sym: str):
        try:
            return await asyncio.wait_for(earnings_svc.get_upcoming_earnings(sym), timeout=6.0)
        except (Exception, asyncio.TimeoutError):
            return None

    results_raw = await asyncio.gather(
        *[_safe_upcoming(sym) for sym in _CALENDAR_UNIVERSE],
        return_exceptions=True,
    )

    today    = date.today()
    cutoff   = today + timedelta(days=days_ahead)
    calendar: dict[str, list] = {}

    for item in results_raw:
        if not item or isinstance(item, Exception):
            continue
        ed = item.earnings_date
        if not ed:
            continue
        try:
            d = date.fromisoformat(str(ed)[:10])
        except ValueError:
            continue
        if d < today or d > cutoff:
            continue
        ds = d.isoformat()
        if ds not in calendar:
            calendar[ds] = []
        calendar[ds].append({
            "symbol":           item.symbol,
            "earnings_date":    ds,
            "eps_estimate":     item.eps_estimate,
            "revenue_estimate": item.revenue_estimate,
        })

    # Sort dates chronologically and build response list
    sorted_dates = sorted(calendar.keys())
    grouped = [
        {"date": d, "events": calendar[d]}
        for d in sorted_dates
    ]

    total_events = sum(len(g["events"]) for g in grouped)
    payload = {
        "days_ahead":   days_ahead,
        "total_events": total_events,
        "groups":       grouped,
        "fetched_at":   datetime.utcnow().isoformat(),
    }

    cache_manager.set(cache_key, payload, ttl=3600 * 6)
    return payload


# ── Pre-earnings AI prediction ────────────────────────────────────────────────

@router.get("/pre-prediction/{symbol}")
async def get_pre_earnings_prediction(symbol: str):
    """
    Quick Claude-powered pre-earnings prediction.

    Uses the symbol's upcoming earnings estimate + 4-quarter EPS history
    to produce a bull / bear / neutral verdict with a 2-sentence rationale.
    Cached 6 hours.
    """
    sym = symbol.upper()
    cache_key = f"pre_prediction:{sym}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    if not settings.ANTHROPIC_API_KEY:
        raise HTTPException(status_code=503, detail="AI service not configured on server.")

    # Fetch earnings data
    try:
        data = await earnings_svc.get_earnings_summary(sym, history_limit=4)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch earnings data: {e}")

    upcoming  = data.get("upcoming", {})
    history   = data.get("history", [])
    earn_date = upcoming.get("earnings_date", "unknown")
    est_eps   = upcoming.get("eps_estimate")
    rev_est   = upcoming.get("revenue_estimate")

    # Build history summary
    hist_lines = []
    for q in history[:4]:
        period = q.get("period", "")
        actual = q.get("eps_actual")
        est    = q.get("eps_estimate")
        surp   = q.get("eps_surprise_pct")
        if actual is not None:
            line = f"  {period}: actual EPS={actual:.2f}"
            if surp is not None:
                line += f"  surprise={surp:+.1f}%"
            hist_lines.append(line)

    history_block = "\n".join(hist_lines) if hist_lines else "  No historical EPS available."

    prompt = (
        f"You are a concise financial analyst. Analyze {sym}'s upcoming earnings.\n\n"
        f"Upcoming earnings date: {earn_date}\n"
        f"EPS estimate: {est_eps if est_eps is not None else 'N/A'}\n"
        f"Revenue estimate: {rev_est if rev_est is not None else 'N/A'}\n\n"
        f"Recent EPS history (last 4 quarters):\n{history_block}\n\n"
        "In exactly 2 sentences, give a bull / bear / neutral pre-earnings verdict "
        "and explain the key risk or catalyst. End your response with one of these "
        "exact labels on a new line: VERDICT: BULLISH | VERDICT: BEARISH | VERDICT: NEUTRAL"
    )

    try:
        result = await claude_svc.generate_analysis(
            system_prompt="You are a concise financial analyst. Be direct and data-driven.",
            user_prompt=prompt,
            max_tokens=150,
        )
        text = result["analysis_text"].strip()
    except Exception as e:
        logger.error(f"[pre-prediction] Claude call failed for {sym}: {e}")
        raise HTTPException(status_code=500, detail="AI prediction failed.")

    # Extract verdict label
    verdict = "NEUTRAL"
    for line in reversed(text.splitlines()):
        line = line.strip()
        if line.startswith("VERDICT:"):
            v = line.replace("VERDICT:", "").strip().upper()
            if v in ("BULLISH", "BEARISH", "NEUTRAL"):
                verdict = v
            break

    # Strip the VERDICT line from display text
    display_text = "\n".join(
        l for l in text.splitlines()
        if not l.strip().startswith("VERDICT:")
    ).strip()

    payload = {
        "symbol":       sym,
        "earnings_date": earn_date,
        "verdict":      verdict,
        "rationale":    display_text,
        "eps_estimate": est_eps,
        "fetched_at":   datetime.utcnow().isoformat(),
    }

    cache_manager.set(cache_key, payload, ttl=3600 * 6)
    return payload


# ── Post-earnings surprise auto-analysis ─────────────────────────────────────

@router.get("/post-analysis/{symbol}")
async def get_post_earnings_analysis(symbol: str):
    """
    Post-earnings surprise auto-analysis.

    Compares the most recent actual EPS vs estimate, computes the surprise %,
    and asks Claude for a 3-sentence analysis of what the surprise means.
    Only runs when actual EPS data is present in the most recent quarter.
    Cached 12 hours.
    """
    sym = symbol.upper()
    cache_key = f"post_analysis:{sym}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    if not settings.ANTHROPIC_API_KEY:
        raise HTTPException(status_code=503, detail="AI service not configured on server.")

    try:
        data = await earnings_svc.get_earnings_summary(sym, history_limit=2)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch earnings data: {e}")

    history = data.get("history", [])
    if not history:
        raise HTTPException(status_code=404, detail="No earnings history available.")

    latest = history[0]
    actual = latest.get("eps_actual")
    if actual is None:
        raise HTTPException(
            status_code=404,
            detail="No actual EPS data for most recent quarter — earnings may not have been reported yet."
        )

    estimate = latest.get("eps_estimate")
    period   = latest.get("period", "")

    # Compute surprise
    if estimate is not None and estimate != 0:
        surprise_pct = ((actual - estimate) / abs(estimate)) * 100
        surprise_str = f"{surprise_pct:+.1f}%"
        beat_miss    = "BEAT" if actual > estimate else "MISSED"
    else:
        surprise_pct = None
        surprise_str = "N/A (no estimate)"
        beat_miss    = "N/A"

    prompt = (
        f"In 3 sentences, analyze {sym}'s {period} earnings result.\n"
        f"Actual EPS: {actual:.2f}\n"
        f"Estimated EPS: {estimate if estimate is not None else 'N/A'}\n"
        f"EPS surprise: {surprise_str} ({beat_miss})\n\n"
        "Explain what this result means for investors, the key driver behind the "
        "beat or miss, and the likely near-term stock reaction."
    )

    try:
        result = await claude_svc.generate_analysis(
            system_prompt="You are a concise earnings analyst. Reply in plain prose, no markdown.",
            user_prompt=prompt,
            max_tokens=200,
        )
        analysis_text = result["analysis_text"].strip()
    except Exception as e:
        logger.error(f"[post-analysis] Claude call failed for {sym}: {e}")
        raise HTTPException(status_code=500, detail="AI analysis failed.")

    payload = {
        "symbol":        sym,
        "period":        period,
        "eps_actual":    actual,
        "eps_estimate":  estimate,
        "surprise_pct":  round(surprise_pct, 2) if surprise_pct is not None else None,
        "beat_miss":     beat_miss,
        "analysis":      analysis_text,
        "fetched_at":    datetime.utcnow().isoformat(),
    }

    cache_manager.set(cache_key, payload, ttl=3600 * 12)
    return payload


# ── Single-symbol earnings (kept last so /calendar etc. aren't swallowed by /{symbol}) ──

@router.get("/{symbol}")
async def get_earnings(
    symbol: str,
    limit: int = Query(8, ge=1, le=20, description="Quarters of history"),
):
    """
    Upcoming earnings date + historical quarterly EPS for a ticker.
    Returns: upcoming (date, eps_estimate, revenue_estimate) + history (8 quarters).
    """
    sym = symbol.upper()
    cache_key = f"earnings:{sym}:{limit}"
    cached = cache_manager.get(cache_key)
    if cached:
        return cached

    data = await earnings_svc.get_earnings_summary(sym, history_limit=limit)

    if not data["history"] and not data["upcoming"]["earnings_date"]:
        raise HTTPException(status_code=404, detail=f"No earnings data for {symbol}")

    cache_manager.set(cache_key, data, ttl=3600 * 6)  # 6hr cache — earnings dates rarely change
    return data
