"""Tool registry — dispatches OpenAI tool call names to backend service calls.

Each tool:
  - Has a narrow, well-typed implementation
  - Wraps existing MarketCoach services (data_fetcher, signal_engine, fred_svc, etc.)
  - Returns a plain dict that is sent back to OpenAI as the function_call_output
  - Declares _extract_primary_metric() so SessionState is updated correctly

Tool routing flow:
  Flutter receives tool_call event from OpenAI WS
  → Flutter POST /api/voice/tools/invoke
  → voice.py calls ToolInvocationHandler.invoke()
  → ToolInvocationHandler calls ToolRegistry.dispatch()
  → Result returned to Flutter, Flutter sends function_call_output to OpenAI WS
"""

from __future__ import annotations

import logging
from typing import Any

from app.models.voice_session import VoiceMode

logger = logging.getLogger(__name__)


class ToolRegistry:
    """Dispatches tool_name → async service call."""

    def __init__(
        self,
        data_fetcher,
        indicator_svc,
        signal_engine,
        fred_svc,
        firestore_db,
    ) -> None:
        self._df = data_fetcher
        self._ind = indicator_svc
        self._sig = signal_engine
        self._fred = fred_svc
        self._db = firestore_db

        self._handlers: dict[str, Any] = {
            "get_asset_snapshot": self._get_asset_snapshot,
            "get_chart_context": self._get_chart_context,
            "get_macro_context": self._get_macro_context,
            "get_portfolio_context": self._get_portfolio_context,
            "get_current_lesson": self._get_current_lesson,
            "get_learning_progress": self._get_learning_progress,
            "get_next_recommended_lesson": self._get_next_recommended_lesson,
            "mark_lesson_checkpoint": self._mark_lesson_checkpoint,
            "get_last_trade": self._get_last_trade,
            "get_recent_trades": self._get_recent_trades,
            "get_trade_behavior_patterns": self._get_trade_behavior_patterns,
            "get_user_coaching_memory": self._get_user_coaching_memory,
        }

    async def dispatch(self, tool_name: str, uid: str, arguments: dict) -> dict:
        handler = self._handlers.get(tool_name)
        if handler is None:
            logger.warning(f"[tool_registry] Unknown tool: {tool_name}")
            return {"error": f"Unknown tool: {tool_name}"}
        try:
            return await handler(uid=uid, **arguments)
        except Exception as exc:
            logger.error(f"[tool_registry] {tool_name} failed: {exc}")
            return {"error": str(exc)}

    # ── Market tools ──────────────────────────────────────────────────────────

    async def _get_asset_snapshot(self, *, uid: str, symbol: str, **_) -> dict:
        """Live price + key indicators for a symbol."""
        symbol = symbol.upper()
        quote = await self._df.get_quote(symbol)
        candles = await self._df.get_candles(symbol, interval="1d", limit=50)

        rsi = None
        macd_signal = "NEUTRAL"
        ema_stack = "MIXED"

        if candles and len(candles) >= 14:
            try:
                signals = self._sig.run(candles, indicators=None)
                rsi = signals.indicators.rsi_value
                macd_signal = signals.indicators.macd_signal
                ema_stack = signals.indicators.ema_stack
                composite = signals.composite_score
                signal_label = signals.signal_label.value
            except Exception:
                composite = 0.0
                signal_label = "NEUTRAL"
        else:
            composite = 0.0
            signal_label = "NEUTRAL"

        return {
            "symbol": symbol,
            "price": quote.price if quote else None,
            "change_pct": quote.change_percent if quote else None,
            "rsi": rsi,
            "macd_signal": macd_signal,
            "ema_stack": ema_stack,
            "composite_score": composite,
            "signal_label": signal_label,
            "_meta": {"metric": "composite_score", "timeframe": "1d"},
        }

    async def _get_chart_context(
        self, *, uid: str, symbol: str, timeframe: str = "1d", indicators: list = None, **_
    ) -> dict:
        """Composite signals + chart patterns for a symbol/timeframe."""
        symbol = symbol.upper()
        candles = await self._df.get_candles(symbol, interval=timeframe, limit=200)
        if not candles:
            return {"error": f"No candle data for {symbol}"}

        signals = self._sig.run(candles, indicators=None)
        return {
            "symbol": symbol,
            "timeframe": timeframe,
            "composite_score": signals.composite_score,
            "signal_label": signals.signal_label.value,
            "rsi": signals.indicators.rsi_value,
            "macd_signal": signals.indicators.macd_signal,
            "ema_stack": signals.indicators.ema_stack,
            "candlestick_pattern": signals.candlestick.pattern,
            "candlestick_signal": signals.candlestick.signal,
            "_meta": {"metric": "composite_score", "timeframe": timeframe},
        }

    async def _get_macro_context(self, *, uid: str, **_) -> dict:
        """Current macro snapshot from FRED."""
        try:
            macro = await self._fred.get_macro_overview()
            return macro if isinstance(macro, dict) else {"data": str(macro)}
        except Exception as exc:
            return {"error": str(exc)}

    async def _get_portfolio_context(self, *, uid: str, **_) -> dict:
        """User's paper trading holdings summary from Firestore."""
        try:
            account_ref = self._db.collection("paper_accounts").document(uid)
            holdings_ref = self._db.collection("paper_holdings").where("user_id", "==", uid)

            account_snap = account_ref.get()
            cash = account_snap.to_dict().get("cash_balance", 0) if account_snap.exists else 0

            holdings = []
            for doc in holdings_ref.stream():
                h = doc.to_dict()
                holdings.append({
                    "symbol": h.get("symbol"),
                    "shares": h.get("shares"),
                    "avg_cost": h.get("avg_cost"),
                })
            return {"cash": cash, "holdings": holdings, "holding_count": len(holdings)}
        except Exception as exc:
            return {"error": str(exc)}

    # ── Lesson tools ──────────────────────────────────────────────────────────

    async def _get_current_lesson(self, *, uid: str, lesson_id: str, **_) -> dict:
        """Fetch lesson metadata + current screen content from Firestore."""
        try:
            lesson_doc = self._db.collection("lessons").document(lesson_id).get()
            if not lesson_doc.exists:
                return {"error": f"Lesson {lesson_id} not found"}
            lesson = lesson_doc.to_dict()

            # Get progress to know current screen
            prog_doc = (
                self._db.collection("users")
                .document(uid)
                .collection("lesson_progress")
                .document(lesson_id)
                .get()
            )
            current_screen_idx = prog_doc.to_dict().get("current_screen", 0) if prog_doc.exists else 0

            # Get the current screen content
            screens = (
                self._db.collection("lessons")
                .document(lesson_id)
                .collection("screens")
                .order_by("order")
                .stream()
            )
            screens_list = [s.to_dict() for s in screens]
            current_screen = screens_list[current_screen_idx] if screens_list else {}

            return {
                "lesson_id": lesson_id,
                "title": lesson.get("title"),
                "level": lesson.get("level"),
                "total_screens": len(screens_list),
                "current_screen_index": current_screen_idx,
                "current_screen_type": current_screen.get("type"),
                "current_screen_content": current_screen.get("content", {}),
                "_meta": {"metric": "lesson_progress", "timeframe": None},
            }
        except Exception as exc:
            return {"error": str(exc)}

    async def _get_learning_progress(self, *, uid: str, **_) -> dict:
        """Summary of user's lesson progress across all lessons."""
        try:
            progress_docs = (
                self._db.collection("users")
                .document(uid)
                .collection("lesson_progress")
                .stream()
            )
            completed, in_progress = [], []
            for doc in progress_docs:
                p = doc.to_dict()
                if p.get("completed"):
                    completed.append(doc.id)
                else:
                    in_progress.append({"lesson_id": doc.id, "screen": p.get("current_screen", 0)})

            return {
                "completed_count": len(completed),
                "completed_lessons": completed,
                "in_progress": in_progress,
            }
        except Exception as exc:
            return {"error": str(exc)}

    async def _get_next_recommended_lesson(self, *, uid: str, **_) -> dict:
        """Rule-based next lesson: first incomplete lesson after latest completed."""
        try:
            all_lessons = list(
                self._db.collection("lessons").order_by("published_at").stream()
            )
            progress_docs = (
                self._db.collection("users")
                .document(uid)
                .collection("lesson_progress")
                .stream()
            )
            completed_ids = {
                doc.id for doc in progress_docs
                if doc.to_dict().get("completed")
            }
            for lesson_doc in all_lessons:
                if lesson_doc.id not in completed_ids:
                    l = lesson_doc.to_dict()
                    return {
                        "lesson_id": lesson_doc.id,
                        "title": l.get("title"),
                        "level": l.get("level"),
                        "why_recommended": "Next lesson in your curriculum sequence.",
                    }
            return {"message": "All available lessons completed!"}
        except Exception as exc:
            return {"error": str(exc)}

    async def _mark_lesson_checkpoint(
        self, *, uid: str, lesson_id: str, screen_id: int, **_
    ) -> dict:
        """Advance lesson progress to a specific screen index."""
        try:
            from google.cloud.firestore import SERVER_TIMESTAMP
            ref = (
                self._db.collection("users")
                .document(uid)
                .collection("lesson_progress")
                .document(lesson_id)
            )
            ref.set(
                {"current_screen": screen_id, "last_accessed_at": SERVER_TIMESTAMP},
                merge=True,
            )
            return {"updated": True, "lesson_id": lesson_id, "current_screen": screen_id}
        except Exception as exc:
            return {"error": str(exc)}

    # ── Trade tools ───────────────────────────────────────────────────────────

    async def _get_last_trade(self, *, uid: str, **_) -> dict:
        """Most recent paper trade for the user."""
        try:
            docs = (
                self._db.collection("paper_transactions")
                .where("user_id", "==", uid)
                .order_by("created_at", direction="DESCENDING")
                .limit(1)
                .stream()
            )
            for doc in docs:
                t = doc.to_dict()
                return {
                    "trade_id": doc.id,
                    "symbol": t.get("symbol"),
                    "side": t.get("side"),
                    "shares": t.get("shares"),
                    "price": t.get("price"),
                    "created_at": str(t.get("created_at")),
                    "stop_loss": t.get("stop_loss"),
                    "take_profit": t.get("take_profit"),
                    "thesis": t.get("thesis"),
                }
            return {"message": "No trades found."}
        except Exception as exc:
            return {"error": str(exc)}

    async def _get_recent_trades(self, *, uid: str, limit: int = 5, **_) -> dict:
        """Recent paper trades with aggregate PnL."""
        try:
            docs = (
                self._db.collection("paper_transactions")
                .where("user_id", "==", uid)
                .order_by("created_at", direction="DESCENDING")
                .limit(limit)
                .stream()
            )
            trades = []
            for doc in docs:
                t = doc.to_dict()
                trades.append({
                    "trade_id": doc.id,
                    "symbol": t.get("symbol"),
                    "side": t.get("side"),
                    "price": t.get("price"),
                    "shares": t.get("shares"),
                    "stop_loss": t.get("stop_loss"),
                })
            return {"trades": trades, "count": len(trades)}
        except Exception as exc:
            return {"error": str(exc)}

    async def _get_trade_behavior_patterns(self, *, uid: str, **_) -> dict:
        """Analyse recent trades for risk patterns."""
        try:
            docs = (
                self._db.collection("paper_transactions")
                .where("user_id", "==", uid)
                .order_by("created_at", direction="DESCENDING")
                .limit(20)
                .stream()
            )
            trades = [doc.to_dict() for doc in docs]
            total = len(trades)
            no_stop = sum(1 for t in trades if not t.get("stop_loss"))
            return {
                "total_trades_analysed": total,
                "missing_stop_loss_count": no_stop,
                "missing_stop_loss_pct": round(no_stop / total * 100, 1) if total else 0,
            }
        except Exception as exc:
            return {"error": str(exc)}

    # ── Coaching tools ────────────────────────────────────────────────────────

    async def _get_user_coaching_memory(self, *, uid: str, **_) -> dict:
        """Top coaching observations for the user from Firestore."""
        try:
            docs = (
                self._db.collection("users")
                .document(uid)
                .collection("coaching_memory")
                .order_by("strength", direction="DESCENDING")
                .limit(5)
                .stream()
            )
            memories = []
            for doc in docs:
                m = doc.to_dict()
                memories.append({"category": m.get("category"), "summary": m.get("summary")})
            return {"memories": memories}
        except Exception as exc:
            return {"error": str(exc)}

    # ── OpenAI tool schemas ───────────────────────────────────────────────────

    def get_openai_tool_schemas(self, mode: VoiceMode) -> list[dict]:
        """Return the OpenAI-format tool definitions for a given session mode."""
        market_tools = [
            {
                "type": "function",
                "name": "get_asset_snapshot",
                "description": "Get live price, RSI, MACD signal, EMA stack, and composite score for a stock or crypto symbol.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "symbol": {"type": "string", "description": "Ticker symbol, e.g. AAPL or BTC-USD"},
                    },
                    "required": ["symbol"],
                },
            },
            {
                "type": "function",
                "name": "get_chart_context",
                "description": "Get detailed chart signals (composite score, MACD, RSI, candlestick pattern) for a symbol and timeframe.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "symbol": {"type": "string"},
                        "timeframe": {"type": "string", "description": "1m, 5m, 15m, 1h, 4h, 1d", "default": "1d"},
                        "indicators": {"type": "array", "items": {"type": "string"}, "description": "e.g. ['rsi', 'macd']"},
                    },
                    "required": ["symbol"],
                },
            },
            {
                "type": "function",
                "name": "get_macro_context",
                "description": "Get current macroeconomic data: fed funds rate, inflation, yield curve, unemployment.",
                "parameters": {"type": "object", "properties": {}},
            },
            {
                "type": "function",
                "name": "get_portfolio_context",
                "description": "Get the user's current paper trading portfolio holdings and cash balance.",
                "parameters": {"type": "object", "properties": {}},
            },
        ]

        lesson_tools = [
            {
                "type": "function",
                "name": "get_current_lesson",
                "description": "Get the user's active lesson content and their current screen.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "lesson_id": {"type": "string", "description": "The Firestore lesson ID"},
                    },
                    "required": ["lesson_id"],
                },
            },
            {
                "type": "function",
                "name": "get_learning_progress",
                "description": "Get a summary of the user's lesson progress: completed lessons and lessons in progress.",
                "parameters": {"type": "object", "properties": {}},
            },
            {
                "type": "function",
                "name": "get_next_recommended_lesson",
                "description": "Get the next lesson the user should take based on their progress.",
                "parameters": {"type": "object", "properties": {}},
            },
        ]

        trade_tools = [
            {
                "type": "function",
                "name": "get_last_trade",
                "description": "Get the user's most recent paper trade including symbol, side, price, and whether a stop-loss was set.",
                "parameters": {"type": "object", "properties": {}},
            },
            {
                "type": "function",
                "name": "get_recent_trades",
                "description": "Get the user's recent paper trades for pattern analysis.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "limit": {"type": "integer", "description": "Number of trades to fetch (max 10)", "default": 5},
                    },
                },
            },
            {
                "type": "function",
                "name": "get_trade_behavior_patterns",
                "description": "Analyse the user's recent trades for risk management patterns, such as missing stop-losses.",
                "parameters": {"type": "object", "properties": {}},
            },
        ]

        coaching_tools = [
            {
                "type": "function",
                "name": "get_user_coaching_memory",
                "description": "Get the top coaching observations about this user (known habits, gaps, patterns).",
                "parameters": {"type": "object", "properties": {}},
            },
        ]

        if mode == VoiceMode.LESSON:
            return market_tools + lesson_tools + coaching_tools
        if mode == VoiceMode.TRADE_DEBRIEF:
            return market_tools + trade_tools + coaching_tools
        # GENERAL: market + coaching (no lesson/trade by default)
        return market_tools + coaching_tools


def extract_primary_metric(tool_name: str, result: dict) -> str | None:
    """Extract the primary metric label from a tool result."""
    meta = result.get("_meta", {})
    if meta.get("metric"):
        return meta["metric"]
    _defaults = {
        "get_asset_snapshot": "composite_score",
        "get_chart_context": "composite_score",
        "get_macro_context": "fed_funds_rate",
        "get_last_trade": "pnl",
        "get_recent_trades": "pnl",
        "get_trade_behavior_patterns": "missing_stop_loss_pct",
        "get_learning_progress": "completion_pct",
    }
    return _defaults.get(tool_name)
