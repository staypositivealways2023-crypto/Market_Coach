"""Shared Firebase auth dependency for non-voice routers.

Re-exports get_verified_uid from voice_auth_service so every router
uses the same token-verification path without duplicating code.

Usage::

    from app.utils.auth import require_auth

    @router.post("/my-endpoint")
    async def my_endpoint(uid: str = Depends(require_auth)):
        ...
"""

from app.services.voice_auth_service import get_verified_uid as require_auth

__all__ = ["require_auth"]
