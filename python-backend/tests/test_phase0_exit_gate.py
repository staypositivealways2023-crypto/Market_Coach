"""
Phase 0 Exit Gate Tests
=======================
Run with:  pytest tests/test_phase0_exit_gate.py -v

ALL tests must pass before moving to Phase 1.
These tests verify infrastructure only — no AI model calls.
"""

import httpx
import psycopg2
import pytest
import os


OLLAMA_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
POSTGRES_DB = os.getenv("POSTGRES_DB", "marketcoach")
POSTGRES_USER = os.getenv("POSTGRES_USER", "mcuser")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "")


# ── Test 1: Ollama is reachable ───────────────────────────────────────────────

def test_ollama_reachable():
    """Ollama API must respond on /api/tags."""
    resp = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=10)
    assert resp.status_code == 200, f"Ollama unreachable: {resp.status_code}"


# ── Test 2: DeepSeek-R1 14B is pulled ────────────────────────────────────────

def test_deepseek_r1_14b_available():
    """deepseek-r1:14b must appear in Ollama model list."""
    resp = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=10)
    assert resp.status_code == 200
    models = [m["name"] for m in resp.json().get("models", [])]
    assert any("deepseek-r1:14b" in m for m in models), (
        f"deepseek-r1:14b not found. Available models: {models}\n"
        "Run: docker exec market-coach-ollama ollama pull deepseek-r1:14b"
    )


# ── Test 3: Mistral is pulled (needed for intent + synthesis) ─────────────────

def test_mistral_available():
    """mistral must appear in Ollama model list."""
    resp = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=10)
    assert resp.status_code == 200
    models = [m["name"] for m in resp.json().get("models", [])]
    assert any("mistral" in m for m in models), (
        f"mistral not found. Available models: {models}\n"
        "Run: docker exec market-coach-ollama ollama pull mistral"
    )


# ── Test 4: nomic-embed-text is pulled (needed for LlamaIndex RAG) ────────────

def test_nomic_embed_available():
    """nomic-embed-text must appear in Ollama model list."""
    resp = httpx.get(f"{OLLAMA_URL}/api/tags", timeout=10)
    assert resp.status_code == 200
    models = [m["name"] for m in resp.json().get("models", [])]
    assert any("nomic-embed-text" in m for m in models), (
        f"nomic-embed-text not found. Available models: {models}\n"
        "Run: docker exec market-coach-ollama ollama pull nomic-embed-text"
    )


# ── Test 5: PostgreSQL is reachable ──────────────────────────────────────────

def test_postgres_reachable():
    """PostgreSQL must accept connections."""
    try:
        conn = psycopg2.connect(
            host=POSTGRES_HOST,
            port=POSTGRES_PORT,
            dbname=POSTGRES_DB,
            user=POSTGRES_USER,
            password=POSTGRES_PASSWORD,
            connect_timeout=5,
        )
        conn.close()
    except psycopg2.OperationalError as e:
        pytest.fail(
            f"Cannot connect to PostgreSQL: {e}\n"
            "Check docker-compose.yml and POSTGRES_PASSWORD in .env"
        )


# ── Test 6: pgvector extension can be enabled ─────────────────────────────────

def test_pgvector_extension():
    """pgvector extension must install cleanly in the marketcoach database."""
    conn = psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        dbname=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
        connect_timeout=5,
    )
    try:
        with conn.cursor() as cur:
            cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
            conn.commit()
            cur.execute("SELECT extname FROM pg_extension WHERE extname = 'vector';")
            row = cur.fetchone()
            assert row is not None, "pgvector extension not available in this Postgres image"
    finally:
        conn.close()


# ── Test 7: DeepSeek-R1 14B produces a <think> block ─────────────────────────

@pytest.mark.slow   # skip with: pytest -m "not slow"
def test_deepseek_r1_generates_cot():
    """
    Smoke test: send a simple financial prompt to DeepSeek-R1 14B and verify
    the response contains a <think> block (Chain-of-Thought).
    This confirms GPU offload is working and the model is functional.
    Expected time: 30–90 seconds on RTX 5060 Ti 16GB.
    """
    payload = {
        "model": "deepseek-r1:14b",
        "prompt": "RSI for AAPL is 78. Is it overbought? Answer briefly.",
        "stream": False,
        "options": {"temperature": 0.3, "num_predict": 800},
    }
    resp = httpx.post(f"{OLLAMA_URL}/api/generate", json=payload, timeout=120)
    assert resp.status_code == 200, f"Ollama generate failed: {resp.status_code}"
    body = resp.json()
    response_text = body.get("response", "")
    # Ollama ≥0.3.8 extracts DeepSeek-R1 thinking into a separate 'thinking'
    # field and strips <think> tags from 'response'. Accept either form.
    thinking_text = body.get("thinking", "")
    has_cot = (
        "<think>" in response_text          # older Ollama — tags still in response
        or bool(thinking_text)              # newer Ollama — extracted to 'thinking'
        or "<think>" in thinking_text       # belt-and-suspenders
    )
    assert has_cot, (
        "DeepSeek-R1 did not emit chain-of-thought. "
        f"response={response_text[:200]!r}  thinking={thinking_text[:200]!r}\n"
        "Verify GPU offload: run `nvidia-smi` during inference and check VRAM usage."
    )
    full_text = response_text + thinking_text
    assert len(full_text) > 50, "Response too short — model may not be working correctly"


# ── Test 8: FastAPI /api/analyst/query endpoint is registered ─────────────────

def test_analyst_endpoint_registered():
    """The /api/analyst/query endpoint must be listed in OpenAPI spec."""
    resp = httpx.get("http://localhost:8000/api/openapi.json", timeout=5)
    assert resp.status_code == 200, "FastAPI is not running on port 8000"
    paths = resp.json().get("paths", {})
    assert "/api/analyst/query" in paths, (
        "Analyst endpoint not registered. "
        "Check that analyst_router is included in app/main.py"
    )


# ── Test 9: Graph smoke test via HTTP ─────────────────────────────────────────

def test_analyst_query_stub_response():
    """
    POST /api/analyst/query must return HTTP 200 with all expected keys.
    Stubs are in place — all phases return placeholder values.
    """
    resp = httpx.post(
        "http://localhost:8000/api/analyst/query",
        json={"message": "What is RSI?", "user_id": "test_phase0"},
        timeout=30,
    )
    assert resp.status_code == 200, f"Unexpected status: {resp.status_code} — {resp.text}"
    body = resp.json()

    required_keys = [
        "thread_id", "intent", "symbol", "cot_thinking",
        "reasoning_answer", "verification_passed", "coach_response",
        "scenario_cards",
    ]
    for key in required_keys:
        assert key in body, f"Missing key in response: {key}"

    assert body["thread_id"], "thread_id must be a non-empty string"
    assert body["scenario_cards"] is not None, "scenario_cards must not be null"
    assert "bull" in body["scenario_cards"], "scenario_cards must have bull key"
