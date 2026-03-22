"""In-memory cache manager"""

from typing import Any, Optional
from datetime import datetime, timedelta
import threading


class CacheManager:
    """Simple in-memory cache with TTL support"""

    def __init__(self):
        self._cache: dict[str, dict[str, Any]] = {}
        self._lock = threading.Lock()

    def get(self, key: str) -> Optional[Any]:
        """Get value from cache"""
        with self._lock:
            if key in self._cache:
                entry = self._cache[key]

                # Check if expired
                if datetime.utcnow() < entry['expires_at']:
                    return entry['value']
                else:
                    # Remove expired entry
                    del self._cache[key]

            return None

    def set(self, key: str, value: Any, ttl: int = 300):
        """Set value in cache with TTL in seconds"""
        with self._lock:
            self._cache[key] = {
                'value': value,
                'expires_at': datetime.utcnow() + timedelta(seconds=ttl)
            }

    def delete(self, key: str):
        """Delete key from cache"""
        with self._lock:
            if key in self._cache:
                del self._cache[key]

    def clear(self):
        """Clear all cache"""
        with self._lock:
            self._cache.clear()

    def cleanup_expired(self):
        """Remove expired entries"""
        with self._lock:
            now = datetime.utcnow()
            expired_keys = [
                key for key, entry in self._cache.items()
                if now >= entry['expires_at']
            ]

            for key in expired_keys:
                del self._cache[key]


# Global cache instance
cache_manager = CacheManager()
