@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - Fix Pages Not Loading
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

echo [*] Flushing DNS...
ipconfig /flushdns

echo.
echo [*] Testing connection to Google...
ping -n 1 google.com >nul
if %errorlevel%==0 (
    echo [OK] Internet connection works
) else (
    echo [ERROR] No internet connection!
    pause
    exit /b 1
)

echo.
echo [*] Starting bypass with working config...
echo.

:retry
winws.exe --wf-tcp=443 --filter-tcp=443 --hostlist=all_services.txt --dpi-desync=split --dpi-desync-split-pos=1 --dpi-desync-ttl=3 --dpi-desync-fooling=badsum --dpi-desync-repeats=2

echo.
echo If pages still don't load, press R to retry with stronger settings
echo or any other key to exit.
echo.
set /p choice="Retry? (R/N): "
if /i "%choice%"=="R" goto stronger
exit /b

:stronger
echo.
echo [*] Trying stronger settings...
winws.exe --wf-tcp=443 --filter-tcp=443 --hostlist=all_services.txt --dpi-desync=disorder --dpi-desync-split-pos=1,2 --dpi-desync-ttl=2 --dpi-desync-fooling=badsum --dpi-desync-repeats=5

pause
