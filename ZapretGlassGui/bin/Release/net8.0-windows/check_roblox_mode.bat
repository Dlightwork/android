@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
echo ==========================================
echo ZAPRET - Roblox Mode Diagnostic
echo ==========================================

cd /d "%~dp0"

echo.
echo [0/8] Checking admin rights...
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARN] Not running as Administrator. Some checks may be incomplete.
) else (
    echo [OK] Administrator privileges detected
)

echo.
echo [1/8] Checking Roblox list files...
if exist "list-roblox.txt" (
    echo [OK] list-roblox.txt found
) else (
    echo [WARN] list-roblox.txt not found, fallback will use roblox_domains.txt
)

if exist "ipset-roblox.txt" (
    echo [OK] ipset-roblox.txt found
) else (
    echo [WARN] ipset-roblox.txt not found, fallback will use roblox_ips.txt
)

echo.
echo [2/8] Checking Windows filtering services...
sc query BFE | findstr /I "RUNNING" >nul
if %errorlevel%==0 (
    echo [OK] Base Filtering Engine BFE is running
) else (
    echo [WARN] BFE is not RUNNING. WinDivert pipeline may fail.
)

echo.
echo [3/8] Checking WinDivert and winws files...
sc query WinDivert >nul 2>&1
if %errorlevel%==0 (
    echo [OK] WinDivert service entry exists
) else (
    echo [WARN] WinDivert service entry not found
)
if exist "WinDivert64.sys" (
    echo [OK] WinDivert64.sys found
) else (
    echo [WARN] WinDivert64.sys not found in current folder
)
if exist "winws.exe" (
    echo [OK] winws.exe found
) else (
    echo [ERROR] winws.exe not found
    goto end
)

echo.
echo [4/8] Checking winws process...
tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" >nul
if errorlevel 1 (
    echo [ERROR] winws.exe is not running.
    echo Start one of these first:
    echo   - zapret_strong_roblox.bat
    echo   - enable_roblox_mode.bat
    echo   - enable_roblox_mode_any.bat
    goto end
) else (
    echo [OK] winws.exe is running
)

echo.
echo [5/8] Reading winws command line...
set "WINWS_CMD="
for /f "usebackq tokens=1,* delims==" %%A in (`wmic process where "name='winws.exe'" get CommandLine /value 2^>nul ^| findstr /I /B "CommandLine="`) do (
    set "WINWS_CMD=%%B"
)

if not defined WINWS_CMD (
    for /f "usebackq delims=" %%L in (`powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='winws.exe'\" | Select-Object -First 1 -ExpandProperty CommandLine)" 2^>nul`) do (
        set "WINWS_CMD=%%L"
    )
)

if not defined WINWS_CMD (
    echo [WARN] Cannot read winws command line.
) else (
    echo [OK] Command line captured.
    echo.
    echo ---- winws command line ----
    echo !WINWS_CMD!
    echo ----------------------------
    echo.
    echo !WINWS_CMD! | findstr /I "1024-65535" >nul && (
        echo [OK] High-port range 1024-65535 is present
    ) || (
        echo [WARN] High-port range 1024-65535 is NOT found
    )
    echo !WINWS_CMD! | findstr /I "dpi-desync-any-protocol=1" >nul && (
        echo [OK] any-protocol mode is present
    ) || (
        echo [WARN] any-protocol mode is NOT found
    )
    echo !WINWS_CMD! | findstr /I "dpi-desync-fake-unknown-udp" >nul && (
        echo [OK] fake-unknown-udp payload is present
    ) || (
        echo [WARN] fake-unknown-udp payload is NOT found
    )
    echo !WINWS_CMD! | findstr /I "ipset-roblox.txt" >nul && (
        echo [INFO] Mode looks like targeted IPSet
    ) || (
        echo [INFO] Mode may be ANY IPSet or legacy profile
    )
)

echo.
echo [6/8] Checking Roblox processes...
set "RBLX_PID="
set "RBLX_LAUNCHER_PID="
for /f "tokens=2 delims=," %%P in ('tasklist /FI "IMAGENAME eq RobloxPlayerBeta.exe" /FO CSV /NH 2^>nul ^| findstr /I "RobloxPlayerBeta.exe"') do set "RBLX_PID=%%~P"
for /f "tokens=2 delims=," %%P in ('tasklist /FI "IMAGENAME eq RobloxPlayerLauncher.exe" /FO CSV /NH 2^>nul ^| findstr /I "RobloxPlayerLauncher.exe"') do set "RBLX_LAUNCHER_PID=%%~P"

if defined RBLX_PID (
    echo [OK] RobloxPlayerBeta.exe PID: !RBLX_PID!
) else (
    echo [WARN] RobloxPlayerBeta.exe is not running
)

if defined RBLX_LAUNCHER_PID (
    echo [OK] RobloxPlayerLauncher.exe PID: !RBLX_LAUNCHER_PID!
) else (
    echo [WARN] RobloxPlayerLauncher.exe is not running
)

echo.
echo [7/8] Showing raw netstat rows for Roblox PIDs...
if defined RBLX_PID (
    echo --- RobloxPlayerBeta.exe ---
    netstat -ano | findstr " !RBLX_PID!"
) else (
    echo --- RobloxPlayerBeta.exe: no rows, process not running ---
)

if defined RBLX_LAUNCHER_PID (
    echo --- RobloxPlayerLauncher.exe ---
    netstat -ano | findstr " !RBLX_LAUNCHER_PID!"
) else (
    echo --- RobloxPlayerLauncher.exe: no rows, process not running ---
)

echo.
echo [8/8] High-port summary using PowerShell...
if defined RBLX_PID call :show_high_ports !RBLX_PID! RobloxPlayerBeta.exe
if defined RBLX_LAUNCHER_PID call :show_high_ports !RBLX_LAUNCHER_PID! RobloxPlayerLauncher.exe
if not defined RBLX_PID (
    if not defined RBLX_LAUNCHER_PID (
        echo [WARN] No Roblox process is running, summary skipped
    )
)

echo.
echo Done.
goto end

:show_high_ports
set "PID=%~1"
set "PROC=%~2"
echo --- %PROC% high-port summary ---
powershell -NoProfile -Command "$pid=%PID%; $tcp=Get-NetTCPConnection -OwningProcess $pid -ErrorAction SilentlyContinue; $udp=Get-NetUDPEndpoint -OwningProcess $pid -ErrorAction SilentlyContinue; $tcpCount=($tcp|Measure-Object).Count; $udpCount=($udp|Measure-Object).Count; $tcpHigh=($tcp|Where-Object { $_.RemotePort -gt 1023 }|Measure-Object).Count; $udpHigh=($udp|Where-Object { $_.LocalPort -gt 1023 }|Measure-Object).Count; Write-Output ('TCP rows: ' + $tcpCount); Write-Output ('TCP remote high-port rows greater-than 1023: ' + $tcpHigh); Write-Output ('UDP endpoint rows: ' + $udpCount); Write-Output ('UDP local high-port rows greater-than 1023: ' + $udpHigh); if($tcpHigh -gt 0){ $tcp | Where-Object { $_.RemotePort -gt 1023 } | Select-Object -First 12 State,LocalAddress,LocalPort,RemoteAddress,RemotePort | Format-Table -AutoSize }"
exit /b 0

:end
pause
