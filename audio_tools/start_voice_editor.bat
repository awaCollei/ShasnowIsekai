@echo off
cd /d "%~dp0.."
where uv >nul 2>nul
if %errorlevel%==0 (
    uv run audio_tools/voice_editor.py
) else (
    py audio_tools/voice_editor.py
)
pause
