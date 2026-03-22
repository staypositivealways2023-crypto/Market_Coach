"""Analysis Rate Limiter - Per-user daily limits for AI analysis"""

from datetime import datetime, timedelta
from typing import Dict, Tuple
import threading
import logging

logger = logging.getLogger(__name__)


class AnalysisRateLimiter:
    """Rate limiter for AI analysis requests - tracks per user/IP"""

    def __init__(
        self,
        guest_daily_limit: int = 5,
        authenticated_daily_limit: int = 20
    ):
        """
        Initialize analysis rate limiter

        Args:
            guest_daily_limit: Max analyses per day for guest users
            authenticated_daily_limit: Max analyses per day for authenticated users
        """
        self.guest_daily_limit = guest_daily_limit
        self.authenticated_daily_limit = authenticated_daily_limit

        # Track: user_id -> (request_count, reset_time)
        self.usage: Dict[str, Tuple[int, datetime]] = {}
        self.lock = threading.Lock()

        logger.info(
            f"Analysis rate limiter initialized: "
            f"guest={guest_daily_limit}/day, "
            f"authenticated={authenticated_daily_limit}/day"
        )

    def can_proceed(self, user_id: str, is_authenticated: bool = False) -> Tuple[bool, int]:
        """
        Check if user can make an analysis request

        Args:
            user_id: User identifier (IP address or user ID)
            is_authenticated: Whether user is authenticated

        Returns:
            Tuple of (can_proceed: bool, remaining_requests: int)
        """

        with self.lock:
            now = datetime.utcnow()

            # Determine limit based on auth status
            limit = (
                self.authenticated_daily_limit
                if is_authenticated
                else self.guest_daily_limit
            )

            # Check if user has existing usage data
            if user_id in self.usage:
                count, reset_time = self.usage[user_id]

                # Reset if past 24 hours
                if now >= reset_time:
                    count = 0
                    reset_time = now + timedelta(days=1)

                # Check if under limit
                if count < limit:
                    self.usage[user_id] = (count + 1, reset_time)
                    remaining = limit - (count + 1)
                    logger.info(
                        f"Analysis request approved for {user_id}: "
                        f"{count + 1}/{limit} (remaining: {remaining})"
                    )
                    return True, remaining
                else:
                    remaining = 0
                    logger.warning(
                        f"Analysis rate limit exceeded for {user_id}: "
                        f"{count}/{limit}"
                    )
                    return False, remaining

            else:
                # First request from this user
                reset_time = now + timedelta(days=1)
                self.usage[user_id] = (1, reset_time)
                remaining = limit - 1

                logger.info(
                    f"First analysis request for {user_id}: "
                    f"1/{limit} (remaining: {remaining})"
                )
                return True, remaining

    def get_remaining(self, user_id: str, is_authenticated: bool = False) -> int:
        """
        Get remaining requests for user

        Args:
            user_id: User identifier
            is_authenticated: Whether user is authenticated

        Returns:
            Number of remaining requests
        """

        with self.lock:
            now = datetime.utcnow()
            limit = (
                self.authenticated_daily_limit
                if is_authenticated
                else self.guest_daily_limit
            )

            if user_id in self.usage:
                count, reset_time = self.usage[user_id]

                # Reset if expired
                if now >= reset_time:
                    return limit

                return max(0, limit - count)

            return limit

    def reset_user(self, user_id: str):
        """Reset rate limit for specific user"""
        with self.lock:
            if user_id in self.usage:
                del self.usage[user_id]
                logger.info(f"Rate limit reset for {user_id}")

    def cleanup_expired(self):
        """Clean up expired entries (call periodically)"""
        with self.lock:
            now = datetime.utcnow()
            expired_users = [
                user_id
                for user_id, (_, reset_time) in self.usage.items()
                if now >= reset_time + timedelta(days=1)  # Keep for extra day
            ]

            for user_id in expired_users:
                del self.usage[user_id]

            if expired_users:
                logger.info(f"Cleaned up {len(expired_users)} expired rate limit entries")


# Global instance
analysis_rate_limiter = AnalysisRateLimiter(
    guest_daily_limit=5,
    authenticated_daily_limit=20
)
