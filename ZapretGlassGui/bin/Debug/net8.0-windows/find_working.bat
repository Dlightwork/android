@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - Finding Working Strategy
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

echo [*] Testing different strategies...
echo.

set "HOSTLIST=all_services.txt"

echo === TEST 1: split + badsum (basic) ===
start "Test 1" cmd /c "winws.exe --wf-tcp=443 --filter-tcp=443 --hostlist=%HOSTLIST% --dpi-desync=split --dpi-desync-split-pos=1 --dpi-desync-ttl=3 --dpi-desync-fooling=badsum --dpi-desync-repeats=3 & pause"

echo Open https://youtube.com in NEW tab and check if it works
echo If YES - close this window and use this strategy
echo If NO - press any key to continue testing...
pause >nul
taskkill /f /im winws.exe 2>nul
timeout /t 1 /nobreak >nul

echo === TEST 2: disorder + badseq ===
start "Test 2" cmd /c "winws.exe --wf-tcp=443 --filter-tcp=443 --hostlist=%HOSTLIST% --dpi-desync=disorder --dpi-desync-split-pos=1,2 --dpi-desync-ttl=2 --dpi-desync-fooling=badseq --dpi-desync-repeats=5 & pause"

echo Check youtube.com again in NEW tab
echo If YES - close and use this
echo If NO - press any key...
pause >nul
taskkill /f /im winws.exe 2>nul
timeout /t 1 /nobreak >nul

echo === TEST 3: fake + disorder (combo) ===
start "Test 3" cmd /c "winws.exe --wf-tcp=443 --filter-tcp=443 --hostlist=%HOSTLIST% --dpi-desync=fake --dpi-desync-ttl=2 --dpi-desync-fooling=badseq --dpi-desync-repeats=10 --new --filter-tcp=443 --hostlist=%HOSTLIST% --dpi-desync=disorder --dpi-desync-split-pos=1 --dpi-desync-ttl=2 --dpi-desync-fooling=badseq --dpi-desync-repeats=5 & pause"

echo Check youtube.com in NEW tab
echo If YES - this is your strategy
echo If NO - press any key...
pause >nul
taskkill /f /im winws.exe 2>nul
timeout /t 1 /nobreak >nul

echo === TEST 4: split with different positions ===
start "Test 4" cmd /c "winws.exe --wf-tcp=443 --filter-tcp=443 --hostlist=%HOSTLIST% --dpi-desync=split --dpi-desync-split-pos=2 --dpi-desync-ttl=3 --dpi-desync-fooling=badsum --dpi-desync-repeats=5 & pause"

echo Check youtube.com in NEW tab
echo Press any key to continue...
pause >nul
taskkill /f /im winws.exe 2>nul
timeout /t 1 /nobreak >nul

echo === TEST 5: disorder with more repeats ===
start "Test 5" cmd /c "winws.exe --wf-tcp=443 --filter-tcp=443 --hostlist=%HOSTLIST% --dpi-desync=disorder --dpi-desync-split-pos=1,2,3 --dpi-desync-ttl=2 --dpi-desync-fooling=badseq,badsum --dpi-desync-repeats=10 & pause"

echo Final test - check youtube.com
echo.
echo If none worked, your provider may use:
echo - IP blocking (not DPI) - need VPN
echo - Deep HTTPS inspection - need GoodbyeDPI with different settings
echo.
pause
