"""
LangGraph Analyst Cycle — stateful 5-node graph.

Flow:
  intent → tool_router → reasoning → verification → [synthesis | retry | error]

The verification node uses a conditional edge:
  - score >= threshold → synthesis → END
  - score <  threshold AND retry_count < max → reasoning (retry)
  - score <  threshold AND retry_count >= max → END (with error)
"""

import logging
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver

from app.graph.state import AnalystState
from app.graph.nodes import intent, tool_router, reasoning, verification, synthesis
from app.config import settings

logger = logging.getLogger(__name__)


def _route_after_verification(state: AnalystState) -> str:
    """Conditional edge: decide what happens after verification.

    The verification node is now the single authority on empty reasoning_answer —
    it hard-fails before any intent bypass so that case always routes through
    retry/error here rather than slipping past as a spurious pass.
    """
    if state.get("verification_passed"):
        logger.info("[graph] verification PASSED — routing to synthesis")
        return "synthesis"

    retry_count = state.get("retry_count", 0)
    max_retries = settings.ANALYST_MAX_RETRIES

    if retry_count < max_retries:
        logger.warning(
            "[graph] verification FAILED (score=%.2f) — retry %d/%d",
            state.get("verification_score", 0.0),
            retry_count,
            max_retries,
        )
        return "retry"

    logger.error(
        "[graph] verification FAILED after %d retries — ending with error",
        retry_count,
    )
    return "error"


def _inject_error(state: AnalystState) -> dict:
    """Terminal error node — surfaces failure to the caller."""
    flagged = state.get("flagged_claims", []) or []
    if flagged and str(flagged[0]).startswith("Deep analysis unavailable:"):
        return {"error": str(flagged[0])}
    return {
        "error": (
            f"Analysis could not be verified after {state.get('retry_count', 0)} retries. "
            f"Flagged issues: {', '.join(flagged or ['unknown'])}"
        )
    }


def build_analyst_graph():
    """Build and compile the analyst StateGraph."""
    graph = StateGraph(AnalystState)

    # ── Register nodes ────────────────────────────────────────────────────────
    graph.add_node("intent",       intent.run)
    graph.add_node("tool_router",  tool_router.run)
    graph.add_node("reasoning",    reasoning.run)
    graph.add_node("verification", verification.run)
    graph.add_node("synthesis",    synthesis.run)
    graph.add_node("error_node",   _inject_error)

    # ── Linear edges ──────────────────────────────────────────────────────────
    graph.set_entry_point("intent")
    graph.add_edge("intent",      "tool_router")
    graph.add_edge("tool_router", "reasoning")
    graph.add_edge("reasoning",   "verification")
    graph.add_edge("synthesis",   END)
    graph.add_edge("error_node",  END)

    # ── Conditional edge after verification ───────────────────────────────────
    graph.add_conditional_edges(
        "verification",
        _route_after_verification,
        {
            "synthesis": "synthesis",
            "retry":     "reasoning",   # loops back with flagged_claims in state
            "error":     "error_node",
        },
    )

    checkpointer = MemorySaver()
    compiled = graph.compile(checkpointer=checkpointer)
    logger.info("[graph] Analyst cycle graph compiled successfully")
    return compiled


# Module-level singleton — imported by the FastAPI router
analyst_graph = build_analyst_graph()
