@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - EMERGENCY MODE
echo For DPI with certificate replacement
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

echo [*] Flushing DNS and resetting network...
ipconfig /flushdns
netsh winsock reset

echo.
echo [*] Starting EMERGENCY bypass...
echo [*] Strategy: fake + disorder + badseq
echo [*] This should bypass certificate injection
echo.

winws.exe ^
    --wf-tcp=443,80 ^
    --filter-tcp=443 ^
    --hostlist=all_services.txt ^
    --dpi-desync=fake ^
    --dpi-desync-ttl=2 ^
    --dpi-desync-fooling=badseq ^
    --dpi-desync-repeats=15 ^
    --new ^
    --filter-tcp=443 ^
    --hostlist=all_services.txt ^
    --dpi-desync=disorder ^
    --dpi-desync-split-pos=1,2,3 ^
    --dpi-desync-ttl=2 ^
    --dpi-desync-fooling=badseq ^
    --dpi-desync-repeats=10

echo.
echo [*] Emergency bypass stopped
pause
