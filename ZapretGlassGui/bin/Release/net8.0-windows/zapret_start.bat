@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - DPI Bypass Tool
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

cd /d "%~dp0"

echo.
echo Select service:
echo 1. YouTube
echo 2. Discord
echo 3. Roblox Strong (winws2 preset)
echo 4. All services (winws2 preset)
echo 5. Roblox (Any High Ports)
echo 6. Roblox Diagnostics
echo 7. Roblox A/B Test (Targeted vs Any)
echo 8. Roblox BIN Rotation Test
echo 9. All Services (Multisplit SNI Auto)
echo 10. Open Glass GUI
echo.

set /p choice="Enter number (1-10): "

if "%choice%"=="1" goto youtube
if "%choice%"=="2" goto discord
if "%choice%"=="3" goto roblox
if "%choice%"=="4" goto all
if "%choice%"=="5" goto roblox_any
if "%choice%"=="6" goto roblox_diag
if "%choice%"=="7" goto roblox_ab
if "%choice%"=="8" goto roblox_bins
if "%choice%"=="9" goto multisplit_auto
if "%choice%"=="10" goto glass_gui

echo Invalid choice
pause
exit /b 1

:youtube
echo.
echo [*] Starting YouTube bypass...
winws.exe --wf-tcp=443 --filter-tcp=443 --hostlist=youtube_domains.txt --dpi-desync=split --dpi-desync-split-pos=1,2 --dpi-desync-ttl=3 --dpi-desync-fooling=badsum --dpi-desync-repeats=3
goto end

:discord
echo.
echo [*] Starting Discord bypass...
winws.exe --wf-tcp=443 --filter-tcp=443 --hostlist=discord_domains.txt --dpi-desync=disorder --dpi-desync-split-pos=1,2 --dpi-desync-ttl=2 --dpi-desync-fooling=badsum --dpi-desync-repeats=4
goto end

:roblox
echo.
echo [*] Starting Roblox strong preset...
call "%~dp0zapret_strong.bat"
goto end

:roblox_any
echo.
echo [*] Starting Roblox bypass (ANY high ports mode)...
call "%~dp0enable_roblox_mode_any.bat"
goto end

:roblox_diag
echo.
echo [*] Running Roblox diagnostics...
call "%~dp0check_roblox_mode.bat"
goto end

:roblox_ab
echo.
echo [*] Running Roblox A/B test...
call "%~dp0ab_test_roblox_modes.bat"
goto end

:roblox_bins
echo.
echo [*] Running Roblox BIN rotation test...
call "%~dp0rotate_bin_test.bat"
goto end

:multisplit_auto
echo.
echo [*] Starting universal multisplit SNI bypass with auto hostlist/ipset...
call "%~dp0zapret_multisplit_auto.bat"
goto end

:glass_gui
echo.
echo [*] Starting Zapret Glass GUI...
call "%~dp0zapret_gui.bat"
goto end

:all
echo.
echo [*] Starting ALL TCP and UDP multisplit_sni profile...
call "%~dp0zapret_multisplit.bat"

:end
echo.
echo [*] Bypass stopped
pause
