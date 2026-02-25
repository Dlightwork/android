@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - DPI Bypass
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

cd /d "%~dp0"

echo.
echo [*] Starting bypass...
echo [*] Strategy: split + badsum
echo [*] Press Ctrl+C to stop
echo.

winws.exe --wf-tcp=443 --filter-tcp=443 --hostlist=all_services.txt --dpi-desync=split --dpi-desync-split-pos=1,2 --dpi-desync-ttl=3 --dpi-desync-fooling=badsum --dpi-desync-repeats=3

echo.
echo [*] Stopped
pause
