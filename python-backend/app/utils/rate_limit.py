"""Shared slowapi limiter singleton.

Import `limiter` into routers and decorate handlers with @limiter.limit("N/minute").
The limiter must also be registered on the FastAPI app in main.py.

Rate limits (per IP):
  /api/chat              60 req/min  — streaming, but each SSE is one request
  /api/analyse/*         10 req/min  — Claude synthesis is expensive
  /api/portfolio/analyse  5 req/min  — heaviest endpoint
  /api/trade-debrief     20 req/min  — shorter Claude call
  everything else        120 req/min — market data reads (default)
"""

from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address, default_limits=["120/minute"])
