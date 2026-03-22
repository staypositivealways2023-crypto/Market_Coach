"""API Rate Limiter"""

from datetime import datetime, timedelta
from collections import deque
import threading


class APIRateLimiter:
    """Rate limiter using sliding window"""

    def __init__(self, max_requests: int = 60, window_seconds: int = 60):
        """
        Initialize rate limiter

        Args:
            max_requests: Maximum requests allowed in window
            window_seconds: Time window in seconds
        """
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self.requests = deque()
        self.lock = threading.Lock()

    def can_proceed(self) -> bool:
        """Check if request can proceed and record it"""
        with self.lock:
            now = datetime.utcnow()

            # Remove expired requests
            cutoff = now - timedelta(seconds=self.window_seconds)
            while self.requests and self.requests[0] < cutoff:
                self.requests.popleft()

            # Check if we're under limit
            if len(self.requests) < self.max_requests:
                self.requests.append(now)
                return True

            return False

    def reset(self):
        """Reset rate limiter"""
        with self.lock:
            self.requests.clear()

    def get_remaining(self) -> int:
        """Get remaining requests in current window"""
        with self.lock:
            now = datetime.utcnow()
            cutoff = now - timedelta(seconds=self.window_seconds)

            # Remove expired requests
            while self.requests and self.requests[0] < cutoff:
                self.requests.popleft()

            return max(0, self.max_requests - len(self.requests))
