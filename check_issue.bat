@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - Diagnostic Check
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

cd /d "%~dp0"

echo.
echo [*] Checking Base Filtering Engine (BFE)...
sc query BFE | findstr /I "RUNNING" >nul
if %errorlevel%==0 (
    echo [OK] BFE service is running
) else (
    echo [WARNING] BFE service is not running!
    echo WinDivert-based filtering may fail until BFE is fixed.
)

echo.
echo [*] Checking WinDivert driver...
sc query WinDivert >nul 2>&1
if %errorlevel%==0 (
    echo [OK] WinDivert driver is installed
) else (
    echo [WARNING] WinDivert driver not found!
    echo Trying to install...
    sc create WinDivert binPath= "%~dp0WinDivert64.sys" type= kernel start= demand 2>nul
)

echo.
echo [*] Checking if winws.exe exists...
if exist "winws.exe" (
    echo [OK] winws.exe found
) else (
    echo [ERROR] winws.exe not found!
    echo Please download Zapret and extract winws.exe here
    pause
    exit /b 1
)

echo.
echo [*] Checking hostlist files...
if exist "all_services.txt" (
    echo [OK] all_services.txt found
    type all_services.txt | find /c /v ""
) else (
    echo [ERROR] all_services.txt not found!
)

echo.
echo [*] Testing basic connectivity...
ping -n 1 8.8.8.8 >nul
if %errorlevel%==0 (
    echo [OK] Internet connection works
) else (
    echo [ERROR] No internet connection!
)

echo.
echo [*] Checking DNS resolution...
nslookup youtube.com >nul 2>&1
if %errorlevel%==0 (
    echo [OK] DNS resolution works
) else (
    echo [WARNING] DNS may be blocked
)

echo.
echo [*] Testing if port 443 is reachable...
powershell -Command "(New-Object Net.Sockets.TcpClient).Connect('google.com', 443)" >nul 2>&1
if %errorlevel%==0 (
    echo [OK] Port 443 is reachable
) else (
    echo [WARNING] Port 443 may be blocked
)

echo.
echo ==========================================
echo DIAGNOSTIC COMPLETE
echo ==========================================
echo.
echo If all checks are [OK] but bypass doesn't work:
echo - Your ISP uses IP blocking (not DPI)
echo - Try using a VPN instead
echo.
echo If you see [ERROR] or [WARNING]:
echo - Fix those issues first
echo.
pause
