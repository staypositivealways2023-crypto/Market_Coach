"""
Pytest configuration for MarketCoach backend tests.

Installs lightweight stubs for Docker-only packages (langgraph, anthropic,
httpx, langchain_ollama) before any test file is collected, then loads .env.
Stubs use try/except so real packages in Docker are left untouched.
"""

import sys
import types
import pathlib


def _mod(name):
    m = types.ModuleType(name)
    sys.modules[name] = m
    return m


# ── langgraph ─────────────────────────────────────────────────────────────────
try:
    import langgraph  # noqa: F401
except ImportError:
    _lg = _mod("langgraph")
    _lg_g = _mod("langgraph.graph")
    _lg_ck = _mod("langgraph.checkpoint")
    _lg_mem = _mod("langgraph.checkpoint.memory")
    _lg_g.END = "__end__"
    class _FakeSG:
        def __init__(self, *a, **kw): pass
        def add_node(self, *a, **kw): pass
        def add_edge(self, *a, **kw): pass
        def set_entry_point(self, *a, **kw): pass
        def add_conditional_edges(self, *a, **kw): pass
        def compile(self, *a, **kw): return self
    _lg_g.StateGraph = _FakeSG
    _lg_mem.MemorySaver = type("MemorySaver", (), {})
    _lg.graph = _lg_g
    _lg.checkpoint = _lg_ck
    _lg_ck.memory = _lg_mem


# ── anthropic ─────────────────────────────────────────────────────────────────
try:
    import anthropic  # noqa: F401
except ImportError:
    _an = _mod("anthropic")
    _an.AsyncAnthropic = type("AsyncAnthropic", (), {"__init__": lambda s, *a, **kw: None})
    _an.APIConnectionError = type("APIConnectionError", (Exception,), {})
    _an.RateLimitError = type("RateLimitError", (Exception,), {})
    _an.APIStatusError = type("APIStatusError", (Exception,), {"status_code": 500})


# ── httpx ─────────────────────────────────────────────────────────────────────
try:
    import httpx  # noqa: F401
except ImportError:
    _hx = _mod("httpx")
    class _HxResp:
        status_code = 500
        content = b""
        text = "stub"
    class _HxClient:
        def __init__(self, *a, **kw): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *a): pass
        async def post(self, *a, **kw): return _HxResp()
    _hx.AsyncClient = _HxClient
    _hx.TimeoutException = type("TimeoutException", (Exception,), {})


# ── langchain_ollama ──────────────────────────────────────────────────────────
try:
    import langchain_ollama  # noqa: F401
except ImportError:
    _lco = _mod("langchain_ollama")
    class _FakeLLM:
        def __init__(self, *a, **kw): pass
        async def ainvoke(self, p): return ""
    _lco.OllamaLLM = _FakeLLM


# ── pydantic_settings ─────────────────────────────────────────────────────────
try:
    import pydantic_settings  # noqa: F401
except ImportError:
    _ps = _mod("pydantic_settings")
    class _BS:
        def __init__(self, **kw):
            for k, v in kw.items():
                setattr(self, k, v)
    _ps.BaseSettings = _BS
    _ps.SettingsConfigDict = lambda **kw: {}


# ── Prevent app.graph.__init__ from running build_analyst_graph() ────────────
# Without this, any import of app.graph.nodes.* triggers __init__.py which
# calls build_analyst_graph() -> langgraph -> ImportError in this environment.
if "app.graph" not in sys.modules:
    _gp = _mod("app.graph")
    _gp.__path__ = [str(pathlib.Path(__file__).parent.parent / "app" / "graph")]
    _gp.__package__ = "app.graph"


# ── Load .env ─────────────────────────────────────────────────────────────────
try:
    from dotenv import load_dotenv
    from pathlib import Path
    load_dotenv(Path(__file__).parent.parent / ".env", override=True)
except ImportError:
    pass


# ── aiohttp (data_fetcher.py) ─────────────────────────────────────────────────
try:
    import aiohttp  # noqa: F401
except ImportError:
    _ah = _mod("aiohttp")
    _ah.ClientSession = type("ClientSession", (), {"__init__": lambda s, *a, **kw: None})
    _ah.ClientError = type("ClientError", (Exception,), {})

# ── ta + pandas (indicator_service.py) ───────────────────────────────────────
try:
    import pandas  # noqa: F401
except ImportError:
    sys.modules.setdefault("pandas", _mod("pandas"))

try:
    import ta  # noqa: F401
except ImportError:
    for _ta_sub in ("ta", "ta.momentum", "ta.trend", "ta.volatility", "ta.volume"):
        sys.modules.setdefault(_ta_sub, _mod(_ta_sub))

# ── yfinance (data_fetcher / valuation) ──────────────────────────────────────
try:
    import yfinance  # noqa: F401
except ImportError:
    sys.modules.setdefault("yfinance", _mod("yfinance"))

# ── firebase_admin (auth / firestore services) ────────────────────────────────
try:
    import firebase_admin  # noqa: F401
except ImportError:
    for _fb in ("firebase_admin", "firebase_admin.credentials", "firebase_admin.firestore",
                "firebase_admin.auth"):
        sys.modules.setdefault(_fb, _mod(_fb))

# ── app.services.__init__ re-exports MarketDataFetcher -- stub it out so
#    importing app.graph.graph doesn't drag in the full services stack.
if "app.services" not in sys.modules:
    _svc = _mod("app.services")
    _svc.__path__ = [str(pathlib.Path(__file__).parent.parent / "app" / "services")]
    _svc.__package__ = "app.services"

# ── Stub heavy graph nodes so graph.py can be imported for _route_after_verification
# Without this, graph.py's module-level imports pull in tool_router -> indicator_service
# -> ta library (not available outside Docker).
# verification.py and synthesis.py are left as real modules (we unit-test those).
for _node_name in ("intent", "tool_router", "reasoning"):
    _node_key = f"app.graph.nodes.{_node_name}"
    if _node_key not in sys.modules:
        _nm = _mod(_node_key)
        async def _stub_run(state):
            return {}
        _nm.run = _stub_run
