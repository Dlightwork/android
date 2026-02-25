@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - HTTP Mode (Port 80)
echo Last attempt - try HTTP instead of HTTPS
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

cd /d "%~dp0"

echo.
echo [*] Stopping any running winws...
taskkill /f /im winws.exe 2>nul
timeout /t 1 /nobreak >nul

echo [*] Starting HTTP bypass...
echo [*] Targeting port 80 instead of 443
echo.

winws.exe ^
    --wf-tcp=80,443 ^
    --filter-tcp=80 ^
    --hostlist=all_services.txt ^
    --dpi-desync=split ^
    --dpi-desync-split-pos=1 ^
    --dpi-desync-ttl=5 ^
    --dpi-desync-fooling=md5sig ^
    --dpi-desync-repeats=6

echo.
echo [*] HTTP bypass stopped
echo.
echo If this doesn't work, your provider uses IP blocking.
echo Solutions:
echo 1. Use a VPN (ProtonVPN, Windscribe, etc.)
echo 2. Use Tor Browser
echo 3. Use GoodbyeDPI with different settings
echo 4. Contact your ISP about the blocking
echo.
pause
