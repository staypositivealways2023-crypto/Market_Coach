@echo off
REM Development startup script for MarketCoach Python Backend (Windows)

echo Starting MarketCoach Backend in development mode...

REM Check if virtual environment exists
if not exist "venv\" (
    echo Creating virtual environment...
    python -m venv venv
)

REM Activate virtual environment
echo Activating virtual environment...
call venv\Scripts\activate.bat

REM Install dependencies
echo Installing dependencies...
pip install -q --upgrade pip
pip install -q -r requirements.txt

REM Check for .env file
if not exist ".env" (
    echo Warning: .env file not found. Copying from .env.example...
    copy .env.example .env
    echo Please update .env with your API keys and Firebase configuration.
    pause
    exit /b 1
)

REM Check for Firebase credentials
if not exist "serviceAccountKey.json" (
    echo Warning: serviceAccountKey.json not found.
    echo Please download from Firebase Console and save in this directory.
    pause
    exit /b 1
)

REM Run the application
echo Starting FastAPI server...
echo API Documentation: http://localhost:8000/api/docs
echo Health Check: http://localhost:8000/health
echo.

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
