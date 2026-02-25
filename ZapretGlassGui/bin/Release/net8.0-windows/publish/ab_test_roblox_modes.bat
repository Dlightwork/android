@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - Roblox A/B Test
echo Targeted IPSet vs Any High Ports
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

cd /d "%~dp0"

echo.
echo [Step 0] Stopping old winws instances...
taskkill /f /im winws.exe >nul 2>&1
timeout /t 1 /nobreak >nul

echo.
echo [Step 1] Start TARGETED mode in a separate window.
start "Roblox Targeted Mode" cmd /c "cd /d \"%~dp0\" && call enable_roblox_mode.bat"
echo Test Roblox launcher and place join in TARGETED mode.
echo Then come back here and press any key.
pause >nul

echo.
echo [Step 2] Run diagnostics for TARGETED mode.
call "%~dp0check_roblox_mode.bat"

echo.
echo [Step 3] Stop TARGETED mode.
taskkill /f /im winws.exe >nul 2>&1
timeout /t 1 /nobreak >nul

echo.
echo [Step 4] Start ANY mode in a separate window.
start "Roblox Any Mode" cmd /c "cd /d \"%~dp0\" && call enable_roblox_mode_any.bat"
echo Test Roblox launcher and place join in ANY mode.
echo Then come back here and press any key.
pause >nul

echo.
echo [Step 5] Run diagnostics for ANY mode.
call "%~dp0check_roblox_mode.bat"

echo.
echo [Step 6] Stop ANY mode.
taskkill /f /im winws.exe >nul 2>&1

echo.
echo A/B test complete.
echo Compare:
echo - place join success
echo - high-port rows in diagnostics
echo - side effects on other apps
pause
