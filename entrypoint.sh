#!/bin/sh
set -e

# Get port from first argument (default: 8000)
PORT="${1:-8000}"

# Run uvicorn with the specified port
exec uvicorn app.main:app --host 0.0.0.0 --port "$PORT"
