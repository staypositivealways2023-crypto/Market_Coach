@echo off
echo Starting dashboard server on http://localhost:8080
echo Open: http://localhost:8080/marketcoach_health_dashboard.html
echo.
echo Press Ctrl+C to stop.
cd /d "%~dp0"
python -m http.server 8080
