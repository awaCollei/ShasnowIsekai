@echo off
title Video Background Remover

echo ========================================
echo    Video Background Remover
echo ========================================
echo.

:: Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Please install Python 3.7+
    pause
    exit /b 1
)

:: Check and install dependencies
echo Checking dependencies...
pip show rembg >nul 2>&1
if errorlevel 1 (
    echo Installing dependencies...
    pip install -r requirements.txt
    if errorlevel 1 (
        echo [ERROR] Failed to install dependencies
        pause
        exit /b 1
    )
)

:: Download model if needed
@REM echo Checking AI model...
@REM python -c "from rembg import new_session; new_session('u2netp')" >nul 2>&1
@REM if errorlevel 1 (
@REM     echo Downloading model (4.7MB)...
@REM     python -c "from rembg import new_session; new_session('u2netp')"
@REM )

:: Start server
echo.
echo Starting server...
start /b python app.py

:: Wait and open browser
echo Waiting for server...
timeout /t 3 /nobreak >nul
start http://localhost:5000

echo.
echo [OK] Server running at http://localhost:5000
echo Press any key to exit (server continues running)...
pause >nul