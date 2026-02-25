@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - NUCLEAR MODE
echo Last resort - all techniques combined
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
timeout /t 2 /nobreak >nul

echo [*] Maximum network reset...
ipconfig /flushdns
ipconfig /release
ipconfig /renew
netsh winsock reset
netsh int ip reset

echo.
echo [*] Starting NUCLEAR bypass...
echo [*] This combines ALL techniques
echo [*] May be slow but should work
echo.

winws.exe ^
    --wf-tcp=443,80 ^
    --wf-udp=443,5000-5500 ^
    --filter-tcp=80 ^
    --hostlist=all_services.txt ^
    --dpi-desync=split ^
    --dpi-desync-split-pos=1 ^
    --dpi-desync-ttl=5 ^
    --dpi-desync-fooling=md5sig ^
    --dpi-desync-repeats=6 ^
    --new ^
    --filter-tcp=443 ^
    --hostlist=all_services.txt ^
    --dpi-desync=fake ^
    --dpi-desync-ttl=3 ^
    --dpi-desync-fooling=badseq,md5sig ^
    --dpi-desync-repeats=20 ^
    --new ^
    --filter-tcp=443 ^
    --hostlist=all_services.txt ^
    --dpi-desync=disorder ^
    --dpi-desync-split-pos=1,2,3,4,5 ^
    --dpi-desync-ttl=2 ^
    --dpi-desync-fooling=badsum,badseq ^
    --dpi-desync-repeats=15 ^
    --new ^
    --filter-udp=443 ^
    --hostlist=all_services.txt ^
    --dpi-desync=fake ^
    --dpi-desync-repeats=10

echo.
echo [*] Nuclear bypass stopped
echo.
echo If this didn't work, your provider likely uses:
echo 1. IP blocking (not DPI) - try VPN
echo 2. Deep packet inspection at ISP level
echo 3. Blocked WinDivert driver
echo.
pause
