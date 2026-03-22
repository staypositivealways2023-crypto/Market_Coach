#!/bin/bash

# Development startup script for MarketCoach Python Backend

echo "Starting MarketCoach Backend in development mode..."

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "Installing dependencies..."
pip install -q --upgrade pip
pip install -q -r requirements.txt

# Check for .env file
if [ ! -f ".env" ]; then
    echo "Warning: .env file not found. Copying from .env.example..."
    cp .env.example .env
    echo "Please update .env with your API keys and Firebase configuration."
    exit 1
fi

# Check for Firebase credentials
if [ ! -f "serviceAccountKey.json" ]; then
    echo "Warning: serviceAccountKey.json not found."
    echo "Please download from Firebase Console and save in this directory."
    exit 1
fi

# Run the application
echo "Starting FastAPI server..."
echo "API Documentation: http://localhost:8000/api/docs"
echo "Health Check: http://localhost:8000/health"
echo ""

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
