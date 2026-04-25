"""
Reset Voice Usage Counter — development utility.

Clears the Redis usage counter and/or session lock for a given Firebase UID
so you can run fresh voice-feature tests without waiting for the billing period
to roll over.

Usage (from python-backend/):
    # Reset usage + lock for a specific UID
    python scripts/reset_voice_limit.py --uid <firebase_uid>

    # Reset for the default test UID defined below
    python scripts/reset_voice_limit.py

    # Show current usage without resetting
    python scripts/reset_voice_limit.py --show

    # Reset only the session lock (keeps usage counters)
    python scripts/reset_voice_limit.py --lock-only

    # Reset only the usage counter (keeps session lock)
    python scripts/reset_voice_limit.py --usage-only

    # Reset usage for a specific billing period
    python scripts/reset_voice_limit.py --period 2026-04

IMPORTANT: This script only works when Redis is reachable (Docker must be running).
           Run: cd python-backend && docker-compose up -d
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import datetime, timezone

# ── Defaults ──────────────────────────────────────────────────────────────────

# Replace with the Firebase UID you see in your app's debug logs, or in the
# Firebase Console → Authentication → Users.
# Your account email: staypositivealways2023@gmail.com
DEFAULT_UID = ""  # Fill in your Firebase UID here, or pass --uid on the CLI

REDIS_URL = "redis://localhost:6379"  # Override if your Redis runs elsewhere


# ── Core logic ────────────────────────────────────────────────────────────────

async def get_redis():
    try:
        import redis.asyncio as aioredis
    except ImportError:
        print("ERROR: redis package not installed.  Run: pip install redis")
        sys.exit(1)
    return aioredis.from_url(REDIS_URL, encoding="utf-8", decode_responses=True)


async def show_status(r, uid: str, period: str):
    usage_key = f"usage:{uid}:{period}"
    lock_key  = f"voice_lock:{uid}"

    raw_usage = await r.get(usage_key)
    lock_val  = await r.get(lock_key)

    print(f"\n{'='*55}")
    print(f"  Voice Usage Status for uid: {uid}")
    print(f"  Billing period: {period}")
    print(f"{'='*55}")

    if raw_usage:
        data = json.loads(raw_usage)
        minutes_used = data['voice_seconds'] / 60
        print(f"  Sessions used  : {data['sessions']}")
        print(f"  Voice minutes  : {minutes_used:.1f} min ({data['voice_seconds']:.0f} s)")
        print(f"  Text requests  : {data.get('text_requests', 0)}")
    else:
        print("  No usage data found (counter is at zero).")

    if lock_val:
        print(f"\n  ⚠  Active session lock: {lock_val}")
    else:
        print("\n  ✓  No session lock (no active session).")

    # Tier limits reference
    print(f"\n  Tier limits:")
    print(f"    free           : 3 sessions / 10 min per month")
    print(f"    pro            : 60 sessions / 60 min per month")
    print(f"    prototype_owner: unlimited")
    print(f"{'='*55}\n")


async def reset_usage(r, uid: str, period: str):
    key = f"usage:{uid}:{period}"
    existed = await r.get(key)
    if existed:
        await r.delete(key)
        data = json.loads(existed)
        print(f"  ✓ Deleted usage key [{key}]")
        print(f"    Was: sessions={data['sessions']}, "
              f"voice_seconds={data['voice_seconds']:.0f}s")
    else:
        print(f"  ℹ No usage key found for [{key}] — already at zero.")


async def reset_lock(r, uid: str):
    key = f"voice_lock:{uid}"
    val = await r.get(key)
    if val:
        await r.delete(key)
        print(f"  ✓ Released session lock [{key}] (was: {val})")
    else:
        print(f"  ℹ No active session lock for [{key}].")


async def main():
    parser = argparse.ArgumentParser(
        description="Reset voice usage counters / session locks in Redis."
    )
    parser.add_argument(
        "--uid", default=DEFAULT_UID,
        help="Firebase UID of the user to reset (required if DEFAULT_UID not set)",
    )
    parser.add_argument(
        "--period",
        default=datetime.now(timezone.utc).strftime("%Y-%m"),
        help="Billing period in YYYY-MM format (default: current month)",
    )
    parser.add_argument(
        "--show", action="store_true",
        help="Show current usage status without making any changes",
    )
    parser.add_argument(
        "--lock-only", action="store_true",
        help="Only release the active session lock (skip usage counter reset)",
    )
    parser.add_argument(
        "--usage-only", action="store_true",
        help="Only reset the usage counter (skip session lock release)",
    )
    parser.add_argument(
        "--redis-url", default=REDIS_URL,
        help=f"Redis connection URL (default: {REDIS_URL})",
    )
    args = parser.parse_args()

    uid = args.uid.strip()
    if not uid:
        print(
            "ERROR: No Firebase UID provided.\n"
            "  Option 1: Pass --uid <your_firebase_uid>\n"
            "  Option 2: Set DEFAULT_UID at the top of this script.\n"
            "\n"
            "Find your UID in:\n"
            "  • Firebase Console → Authentication → Users\n"
            "  • App debug logs: look for 'uid=' in voice session logs\n"
            "  • Flutter: FirebaseAuth.instance.currentUser?.uid"
        )
        sys.exit(1)

    global REDIS_URL
    REDIS_URL = args.redis_url

    try:
        r = await get_redis()
        # Quick connectivity check
        await r.ping()
    except Exception as e:
        print(f"ERROR: Cannot connect to Redis at {REDIS_URL}\n  {e}")
        print("\nMake sure Docker is running:")
        print("  cd python-backend && docker-compose up -d")
        sys.exit(1)

    period = args.period
    print(f"\nConnected to Redis at {REDIS_URL}")

    if args.show:
        await show_status(r, uid, period)
        return

    print(f"\nResetting voice limits for uid={uid} period={period}\n")

    if args.lock_only:
        await reset_lock(r, uid)
    elif args.usage_only:
        await reset_usage(r, uid, period)
    else:
        # Default: reset both
        await reset_usage(r, uid, period)
        await reset_lock(r, uid)

    print()
    await show_status(r, uid, period)
    print("Done. You can now start a fresh voice session.\n")

    await r.aclose()


if __name__ == "__main__":
    asyncio.run(main())
