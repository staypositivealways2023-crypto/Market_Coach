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
    """Conditional edge: decide what happens after verification."""
    if state.get("verification_passed"):
        # Defense-in-depth: even if verification passed, refuse to route to synthesis
        # when reasoning_answer is empty.  This closes the hallucination window that
        # occurs when the verification bypass auto-passed an empty answer.
        reasoning = state.get("reasoning_answer") or ""
        if not reasoning.strip():
            logger.error(
                "[graph] verification passed but reasoning_answer is empty — "
                "routing to error_node to prevent synthesis hallucination"
            )
            return "error"
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
    return {
        "error": (
            f"Analysis could not be verified after {state.get('retry_count', 0)} retries. "
            f"Flagged issues: {', '.join(state.get('flagged_claims', []) or ['unknown'])}"
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
