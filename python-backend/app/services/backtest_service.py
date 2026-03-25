"""
Backtest Service — loads pre-computed pattern win rates from data/backtest_table.json.

The table is pre-seeded from Bulkowski 'Encyclopedia of Chart Patterns' (2021)
and can be regenerated with scripts/build_backtest_table.py using live OHLCV data.

Usage:
    from app.services.backtest_service import BacktestService
    svc = BacktestService()
    result = svc.lookup("BULL_FLAG", "1d")
    # -> {"win_rate": 0.67, "avg_gain_pct": 5.2, "sample_count": 312}
"""

import json
import logging
from pathlib import Path
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)

# Resolve path relative to this file — works in any working directory
_TABLE_PATH = Path(__file__).parent.parent.parent / "data" / "backtest_table.json"

# Timeframe fallback chain: if exact interval not in table, use nearest equivalent
_INTERVAL_ALIASES: Dict[str, list] = {
    "1m":  ["1m", "5m", "1h", "1d"],
    "5m":  ["5m", "15m", "1h", "1d"],
    "15m": ["15m", "1h", "4h", "1d"],
    "30m": ["1h", "4h", "1d"],
    "1h":  ["1h", "4h", "1d"],
    "2h":  ["4h", "1h", "1d"],
    "4h":  ["4h", "1d", "1h"],
    "12h": ["1d", "4h", "1wk"],
    "1d":  ["1d", "4h", "1wk"],
    "1wk": ["1wk", "1d"],
    "1w":  ["1wk", "1d"],
}


class BacktestService:
    """Loads and queries the pattern backtest lookup table."""

    _instance: Optional["BacktestService"] = None
    _table: Dict[str, Any] = {}
    _loaded: bool = False

    def __init__(self):
        if not BacktestService._loaded:
            self._load()

    def _load(self):
        try:
            with open(_TABLE_PATH, "r", encoding="utf-8") as f:
                BacktestService._table = json.load(f)
            BacktestService._loaded = True
            patterns = [k for k in BacktestService._table if not k.startswith("_")]
            logger.info(f"[backtest] Loaded {len(patterns)} patterns from {_TABLE_PATH}")
        except FileNotFoundError:
            logger.warning(f"[backtest] Table not found at {_TABLE_PATH} — probabilities will use formula fallback")
            BacktestService._table = {}
            BacktestService._loaded = True
        except Exception as e:
            logger.error(f"[backtest] Failed to load table: {e}")
            BacktestService._table = {}
            BacktestService._loaded = True

    def lookup(
        self,
        pattern_type: str,
        interval: str = "1d",
    ) -> Optional[Dict[str, Any]]:
        """
        Look up backtest stats for a given pattern and interval.

        Returns dict with:
          win_rate         float  0-1
          avg_gain_pct     float  (positive = bullish direction)
          avg_loss_pct     float  (negative = against direction)
          sample_count     int
          median_bars_to_resolution  int

        Returns None if pattern not in table.
        """
        pattern_data = BacktestService._table.get(pattern_type)
        if not pattern_data or isinstance(pattern_data, str):
            return None

        # Try exact interval then fallback chain
        candidates = _INTERVAL_ALIASES.get(interval.lower(), [interval, "1d"])
        for candidate in candidates:
            entry = pattern_data.get(candidate)
            if entry:
                return {**entry, "interval_used": candidate}

        return None

    def get_win_rate(self, pattern_type: str, interval: str = "1d") -> Optional[float]:
        """Convenience: returns just win_rate as 0-1 float, or None."""
        result = self.lookup(pattern_type, interval)
        return result.get("win_rate") if result else None

    def get_sample_count(self, pattern_type: str, interval: str = "1d") -> int:
        """Convenience: returns sample_count, or 0 if not found."""
        result = self.lookup(pattern_type, interval)
        return result.get("sample_count", 0) if result else 0

    def available_patterns(self) -> list:
        return [k for k in BacktestService._table if not k.startswith("_")]


# Module-level singleton
_backtest_svc: Optional[BacktestService] = None


def get_backtest_service() -> BacktestService:
    global _backtest_svc
    if _backtest_svc is None:
        _backtest_svc = BacktestService()
    return _backtest_svc
