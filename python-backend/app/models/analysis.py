"""Analysis Models - AI-generated market analysis"""

from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional


class AIAnalysisResponse(BaseModel):
    """Response model for AI-generated market analysis"""

    symbol: str = Field(..., description="Stock ticker symbol")
    analysis_text: str = Field(..., description="Markdown-formatted analysis from Claude")
    timestamp: datetime = Field(..., description="When analysis was generated")
    is_cached: bool = Field(default=False, description="Whether result is from cache")
    tokens_used: Optional[int] = Field(None, description="Number of tokens used by Claude API")

    class Config:
        json_schema_extra = {
            "example": {
                "symbol": "AAPL",
                "analysis_text": "## Market Context\n\nApple (AAPL) is trading at...",
                "timestamp": "2025-01-15T10:30:00Z",
                "is_cached": False,
                "tokens_used": 1450
            }
        }
