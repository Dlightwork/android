@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - Roblox Mode (Targeted IPSet)
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
set "IPSET=ipset-roblox.txt"

if not exist "%HOSTLIST%" set "HOSTLIST=roblox_domains.txt"
if not exist "%IPSET%" set "IPSET=roblox_ips.txt"

echo.
echo [*] Stopping old winws instances...
taskkill /f /im winws.exe >nul 2>&1
timeout /t 1 /nobreak >nul

echo.
echo [*] Starting Roblox targeted mode...
echo [*] Hostlist: %HOSTLIST%
echo [*] IP set:   %IPSET%
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
    --ipset=%IPSET% ^
    --dpi-desync=fake ^
    --dpi-desync-repeats=12 ^
    --dpi-desync-any-protocol=1 ^
    --dpi-desync-fake-unknown-udp=quic_initial_www_google_com.bin ^
    --dpi-desync-cutoff=n3

echo.
echo [*] Roblox targeted mode stopped
pause
