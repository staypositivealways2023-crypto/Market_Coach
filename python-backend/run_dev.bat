@echo off
REM ============================================================
REM  MarketCoach Backend — dev startup (Windows)
REM  ALWAYS use this script, not "python -m uvicorn" directly.
REM  It activates the venv that has all packages installed.
REM ============================================================
echo.
echo  MarketCoach Backend — starting...
echo.

REM Must be run from the python-backend directory
if not exist "app\main.py" (
    echo ERROR: Run this script from inside the python-backend folder.
    echo   cd python-backend
    echo   run_dev.bat
    pause
    exit /b 1
)

REM ── Virtual environment ──────────────────────────────────────
if not exist "venv\" (
    echo [1/4] Creating virtual environment...
    python -m venv venv
) else (
    echo [1/4] Virtual environment found.
)

echo [2/4] Activating virtual environment...
call venv\Scripts\activate.bat

REM ── Dependencies ─────────────────────────────────────────────
echo [3/4] Installing / updating dependencies...
pip install -q --upgrade pip
pip install -q -r requirements.txt

REM ── Pre-flight checks ────────────────────────────────────────
echo [4/4] Running pre-flight checks...

if not exist ".env" (
    echo.
    echo  WARNING: .env not found — copying from .env.example
    copy .env.example .env >nul
    echo  Please fill in your API keys in python-backend\.env then restart.
    pause
    exit /b 1
)

if not exist "serviceAccountKey.json" (
    echo.
    echo  WARNING: serviceAccountKey.json not found.
    echo  Download it from Firebase Console ^> Project Settings ^> Service Accounts
    echo  and save it as python-backend\serviceAccountKey.json
    echo.
    echo  The backend will still start but Firebase auth will be limited.
)

REM ── Launch ───────────────────────────────────────────────────
echo.
echo  Backend starting on http://127.0.0.1:8000
echo  API docs:     http://127.0.0.1:8000/api/docs
echo  Health check: http://127.0.0.1:8000/health
echo.

uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
