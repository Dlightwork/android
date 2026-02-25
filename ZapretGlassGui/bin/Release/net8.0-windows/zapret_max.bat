@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - MAXIMUM POWER MODE
echo For severe DPI blocking
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

cd /d "%~dp0"

echo.
echo [*] Starting MAXIMUM bypass...
echo [*] fake + disorder + maximum repeats
echo.

winws.exe ^
    --wf-tcp=443,80 ^
    --filter-tcp=443 ^
    --hostlist=all_services.txt ^
    --dpi-desync=fake ^
    --dpi-desync-ttl=2 ^
    --dpi-desync-fooling=badsum ^
    --dpi-desync-repeats=10 ^
    --new ^
    --filter-tcp=443 ^
    --hostlist=all_services.txt ^
    --dpi-desync=disorder ^
    --dpi-desync-split-pos=1,2,3,5 ^
    --dpi-desync-ttl=2 ^
    --dpi-desync-fooling=badsum,badseq ^
    --dpi-desync-repeats=7

echo.
echo [*] Maximum bypass stopped
pause
