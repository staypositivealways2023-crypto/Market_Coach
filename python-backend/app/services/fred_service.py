"""FRED (Federal Reserve Economic Data) Service — macro indicators"""

import aiohttp
from typing import Optional, List
from datetime import datetime
import logging

from app.config import settings

logger = logging.getLogger(__name__)

BASE_URL = "https://api.stlouisfed.org/fred"

# Key macro series
SERIES = {
    "fed_funds_rate":  "FEDFUNDS",   # Federal funds rate (monthly %)
    "cpi":             "CPIAUCSL",   # Consumer Price Index
    "inflation_yoy":   "FPCPITOTLZGUSA",  # US inflation YoY %
    "yield_curve":     "T10Y2Y",     # 10Y-2Y spread (daily) — negative = inverted
    "unemployment":    "UNRATE",     # Unemployment rate (monthly %)
    "gdp_growth":      "A191RL1Q225SBEA",  # Real GDP growth QoQ %
    "dxy":             "DTWEXBGS",   # US Dollar index
}


class MacroDataPoint:
    def __init__(self, date: str, value: Optional[float]):
        self.date = date
        self.value = value

    def to_dict(self):
        return {"date": self.date, "value": self.value}


class FredService:
    """Fetches macroeconomic data from FRED API (St. Louis Fed)"""

    def __init__(self):
        self.api_key = getattr(settings, "FRED_API_KEY", "") or ""
        if not self.api_key:
            logger.warning("FRED_API_KEY not configured — macro data unavailable")

    def _params(self, extra: dict = {}) -> dict:
        p = {"file_type": "json", "sort_order": "desc"}
        if self.api_key:
            p["api_key"] = self.api_key
        p.update(extra)
        return p

    async def get_series(
        self, series_id: str, limit: int = 12
    ) -> List[MacroDataPoint]:
        """Fetch recent observations for a FRED series"""
        try:
            url = f"{BASE_URL}/series/observations"
            params = self._params({"series_id": series_id, "limit": limit})

            async with aiohttp.ClientSession() as session:
                async with session.get(url, params=params) as resp:
                    if resp.status != 200:
                        logger.warning(f"FRED {series_id}: HTTP {resp.status}")
                        return []
                    data = await resp.json()

            observations = data.get("observations", [])
            result = []
            for obs in observations:
                raw = obs.get("value", ".")
                value = None if raw == "." else float(raw)
                result.append(MacroDataPoint(date=obs["date"], value=value))

            return result

        except Exception as e:
            logger.error(f"FRED error for {series_id}: {e}")
            return []

    async def get_latest(self, series_id: str) -> Optional[MacroDataPoint]:
        """Get the single most recent value for a series"""
        points = await self.get_series(series_id, limit=5)
        # Skip None values (FRED sometimes has trailing missing data)
        for p in points:
            if p.value is not None:
                return p
        return None

    async def get_macro_overview(self) -> dict:
        """Fetch all key macro indicators in one call — used by /api/macro/overview"""
        import asyncio

        if not self.api_key:
            # No API key — return structured unavailable response so MacroCard shows a message
            overview = {key: None for key in SERIES}
            overview["fetched_at"] = datetime.utcnow().isoformat()
            overview["unavailable_reason"] = "FRED_API_KEY not configured"
            return overview

        keys = list(SERIES.keys())
        series_ids = list(SERIES.values())

        results = await asyncio.gather(
            *[self.get_latest(sid) for sid in series_ids],
            return_exceptions=True
        )

        overview = {}
        for key, result in zip(keys, results):
            if isinstance(result, Exception) or result is None:
                overview[key] = None
            else:
                overview[key] = result.to_dict()

        overview["fetched_at"] = datetime.utcnow().isoformat()
        return overview

    async def get_series_history(self, series_id: str, limit: int = 24) -> List[dict]:
        """Historical series data for charting"""
        points = await self.get_series(series_id, limit=limit)
        return [p.to_dict() for p in reversed(points)]  # chronological order

    async def get_macro_regime(self, symbol: str) -> dict:
        """
        Classify macro regime for a symbol using FRED data.
        Returns regime (Risk-On / Risk-Off / Neutral), drivers, and confidence.
        """
        import asyncio

        if not self.api_key:
            return {
                "symbol": symbol,
                "regime": "Neutral",
                "confidence": 0.0,
                "drivers": [],
                "unavailable_reason": "FRED_API_KEY not configured",
            }

        # Fetch the three key signals concurrently
        yield_pt, fed_pt, cpi_pt = await asyncio.gather(
            self.get_latest(SERIES["yield_curve"]),
            self.get_latest(SERIES["fed_funds_rate"]),
            self.get_latest(SERIES["cpi"]),
            return_exceptions=True,
        )

        drivers = []
        score = 0  # positive = risk-on, negative = risk-off

        # Yield curve: positive spread = healthy (risk-on), inverted = risk-off
        yield_val = yield_pt.value if isinstance(yield_pt, MacroDataPoint) and yield_pt else None
        if yield_val is not None:
            if yield_val > 0.5:
                score += 2
                drivers.append({"factor": "Yield Curve", "signal": "Positive", "value": round(yield_val, 2)})
            elif yield_val < 0:
                score -= 2
                drivers.append({"factor": "Yield Curve", "signal": "Inverted", "value": round(yield_val, 2)})
            else:
                drivers.append({"factor": "Yield Curve", "signal": "Flat", "value": round(yield_val, 2)})

        # Fed funds rate: high rates (>5%) = tightening pressure = slightly risk-off
        fed_val = fed_pt.value if isinstance(fed_pt, MacroDataPoint) and fed_pt else None
        if fed_val is not None:
            if fed_val > 5.0:
                score -= 1
                drivers.append({"factor": "Fed Funds Rate", "signal": "Elevated", "value": round(fed_val, 2)})
            elif fed_val < 2.0:
                score += 1
                drivers.append({"factor": "Fed Funds Rate", "signal": "Accommodative", "value": round(fed_val, 2)})
            else:
                drivers.append({"factor": "Fed Funds Rate", "signal": "Neutral", "value": round(fed_val, 2)})

        # CPI: high inflation (>4%) = risk-off pressure
        cpi_val = cpi_pt.value if isinstance(cpi_pt, MacroDataPoint) and cpi_pt else None
        if cpi_val is not None:
            # CPI is index level; derive signal from magnitude (>320 = elevated modern-day)
            cpi_signal = "Elevated" if cpi_val > 310 else "Moderate"
            if cpi_val > 310:
                score -= 1
            drivers.append({"factor": "CPI", "signal": cpi_signal, "value": round(cpi_val, 2)})

        # Classify regime from score
        if score >= 2:
            regime = "Risk-On"
        elif score <= -2:
            regime = "Risk-Off"
        else:
            regime = "Neutral"

        total_factors = max(len(drivers), 1)
        confidence = round(min(abs(score) / total_factors, 1.0), 2)

        return {
            "symbol": symbol,
            "regime": regime,
            "confidence": confidence,
            "score": score,
            "drivers": drivers,
        }
