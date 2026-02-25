@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - Roblox Mode (Any High Ports)
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

cd /d "%~dp0"
set "GameFilter=1024-65535"
set "HOSTLIST=list-roblox.txt"

if not exist "%HOSTLIST%" set "HOSTLIST=roblox_domains.txt"

echo.
echo [*] Stopping old winws instances...
taskkill /f /im winws.exe >nul 2>&1
timeout /t 1 /nobreak >nul

echo.
echo [*] Starting Roblox ANY mode...
echo [*] WARNING: high-port traffic is processed globally.
echo [*] Hostlist: %HOSTLIST%
echo.

winws.exe ^
    --wf-tcp=80,443,2053,2083,2087,2096,8443,%GameFilter% ^
    --wf-udp=443,19294-19344,50000-50100,%GameFilter% ^
    --filter-tcp=443 ^
    --hostlist=%HOSTLIST% ^
    --dpi-desync=fake ^
    --dpi-desync-repeats=6 ^
    --new ^
    --filter-udp=%GameFilter% ^
    --dpi-desync=fake ^
    --dpi-desync-repeats=12 ^
    --dpi-desync-any-protocol=1 ^
    --dpi-desync-fake-unknown-udp=quic_initial_www_google_com.bin ^
    --dpi-desync-cutoff=n3 ^
    --new ^
    --filter-tcp=%GameFilter% ^
    --dpi-desync=syndata

echo.
echo [*] Roblox ANY mode stopped
pause
