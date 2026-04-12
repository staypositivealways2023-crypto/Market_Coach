"""Claude AI Service - Generate market analysis using Anthropic's Claude API"""

import anthropic
from typing import Dict, Optional
import logging
from app.config import settings

logger = logging.getLogger(__name__)


class ClaudeService:
    """Service for generating AI-powered market analysis"""

    def __init__(self):
        """Initialize Claude service with API key"""
        if not settings.ANTHROPIC_API_KEY:
            logger.warning("ANTHROPIC_API_KEY not configured")
            self.client = None
        else:
            self.client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)

        # Model selection — configurable via CLAUDE_MODEL env var.
        # Default: Sonnet 4.6 for richer macro/pattern reasoning (Phase D).
        # Set CLAUDE_MODEL=claude-haiku-4-5-20251001 to fall back to Haiku (faster/cheaper).
        import os
        self.model = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-6")
        self.max_tokens = 4096

    async def generate_analysis(
        self,
        system_prompt: str,
        user_prompt: str,
        max_tokens: Optional[int] = None,
    ) -> Dict[str, any]:
        """
        Generate analysis using Claude API

        Args:
            system_prompt: System instructions for Claude's persona/behavior
            user_prompt: User message containing market data to analyze

        Returns:
            Dict with 'analysis_text' (str) and 'tokens_used' (int)

        Raises:
            ValueError: If API key not configured
            anthropic.RateLimitError: If rate limit exceeded
            anthropic.APIError: For other API errors
        """

        if not self.client:
            raise ValueError("Anthropic API key not configured")

        try:
            logger.info(f"Generating analysis with {self.model}")

            # Call Claude API
            response = await self.client.messages.create(
                model=self.model,
                max_tokens=max_tokens or self.max_tokens,
                system=system_prompt,
                messages=[
                    {
                        "role": "user",
                        "content": user_prompt
                    }
                ]
            )

            # Extract text from response
            analysis_text = response.content[0].text

            # Calculate token usage
            tokens_used = response.usage.input_tokens + response.usage.output_tokens

            logger.info(
                f"Analysis generated successfully. "
                f"Tokens: {tokens_used} "
                f"(input: {response.usage.input_tokens}, "
                f"output: {response.usage.output_tokens})"
            )

            return {
                "analysis_text": analysis_text,
                "tokens_used": tokens_used
            }

        except anthropic.RateLimitError as e:
            logger.error(f"Rate limit exceeded: {e}")
            raise

        except anthropic.APITimeoutError as e:
            logger.error(f"API timeout: {e}")
            raise

        except anthropic.APIError as e:
            logger.error(f"Claude API error: {e}")
            raise

        except Exception as e:
            logger.error(f"Unexpected error generating analysis: {e}")
            raise
