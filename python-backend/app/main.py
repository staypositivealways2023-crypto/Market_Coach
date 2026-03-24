"""FastAPI Application Entry Point"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
import logging

from app.routers import internal, market, indicators, analysis, macro, news, earnings, fundamentals, portfolio
from app.routers import analyse as analyse_router
from app.routers import chat as chat_router
from app.config import settings
from app.utils.logger import setup_logger

# Setup logging
logger = setup_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifecycle manager for FastAPI app"""
    logger.info("Starting MarketCoach Backend API...")
    logger.info(f"Environment: {settings.ENVIRONMENT}")
    logger.info(f"Firebase Project: {settings.FIREBASE_PROJECT_ID}")
    yield
    logger.info("Shutting down MarketCoach Backend API...")


# Create FastAPI app
app = FastAPI(
    title="MarketCoach Backend API",
    description="Market data, technical indicators, and valuation services",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(internal.router, prefix="/internal", tags=["Internal"])
app.include_router(market.router, prefix="/api/market", tags=["Market Data"])
app.include_router(indicators.router, prefix="/api/indicators", tags=["Technical Indicators"])
app.include_router(analysis.router, prefix="/api", tags=["AI Analysis"])
app.include_router(macro.router, prefix="/api/macro", tags=["Macro Data"])
app.include_router(news.router, prefix="/api/news", tags=["News"])
app.include_router(earnings.router, prefix="/api/earnings", tags=["Earnings"])
app.include_router(fundamentals.router, prefix="/api/fundamentals", tags=["Fundamentals"])
app.include_router(analyse_router.router, prefix="/api", tags=["Signal Engine"])
app.include_router(portfolio.router, prefix="/api/portfolio", tags=["Portfolio"])
app.include_router(chat_router.router, prefix="/api", tags=["Chat"])


@app.get("/")
async def root():
    """Root endpoint - health check"""
    return {
        "service": "MarketCoach Backend API",
        "version": "0.1.0",
        "status": "operational",
        "docs": "/api/docs"
    }


@app.get("/health")
async def health_check():
    """Health check endpoint for monitoring"""
    return {
        "status": "healthy",
        "environment": settings.ENVIRONMENT,
        "firebase_configured": bool(settings.FIREBASE_PROJECT_ID)
    }


@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler"""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "detail": str(exc) if settings.DEBUG else "An unexpected error occurred"
        }
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.DEBUG,
        log_level="info"
    )
