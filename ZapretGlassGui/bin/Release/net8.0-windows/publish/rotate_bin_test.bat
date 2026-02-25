@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
echo ==========================================
echo ZAPRET - Roblox BIN Rotation Test
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

cd /d "%~dp0"
set "GameFilterTCP=1024-65535"
set "GameFilterUDP=1024-65535"
set "RH1=lists\roblox_domains.txt"
set "RH2=lists\list-roblox.txt"
set "RI1=lists\ipset-roblox.txt"
set "RI2=lists\roblox_ips.txt"

if not exist "%RH1%" set "RH1=roblox_domains.txt"
if not exist "%RH2%" set "RH2=list-roblox.txt"
if not exist "%RH2%" set "RH2=%RH1%"
if not exist "%RI1%" set "RI1=ipset-roblox.txt"
if not exist "%RI2%" set "RI2=roblox_ips.txt"
if not exist "%RI2%" set "RI2=%RI1%"

set "BIN_DIR=bin"
if not exist "%BIN_DIR%\*.bin" set "BIN_DIR=."

set /a COUNT=0
set "FAST_MODE=1"
if /i "%~1"=="full" set "FAST_MODE=0"

if "%FAST_MODE%"=="1" (
    call :add_bin_if_exists "%BIN_DIR%\unknown_udp.bin"
    call :add_bin_if_exists "%BIN_DIR%\quic_initial_www_google_com.bin"
    call :add_bin_if_exists "%BIN_DIR%\fake_quic.bin"
    call :add_bin_if_exists "%BIN_DIR%\quic_1.bin"
    call :add_bin_if_exists "%BIN_DIR%\quic_2.bin"
    call :add_bin_if_exists "%BIN_DIR%\tls_clienthello_www_google_com.bin"
    call :add_bin_if_exists "%BIN_DIR%\tls_clienthello_4pda_to.bin"
    call :add_bin_if_exists "%BIN_DIR%\tls_clienthello_max_ru.bin"
    call :add_bin_if_exists "%BIN_DIR%\quic_initial_google_com.bin"
    call :add_bin_if_exists "%BIN_DIR%\zero_256.bin"
    if %COUNT% EQU 0 (
        echo [!] Priority bin list is empty. Switching to full scan.
        set "FAST_MODE=0"
    )
)

if "%FAST_MODE%"=="0" (
    for %%F in ("%BIN_DIR%\*.bin") do call :add_bin_if_exists "%%~fF"
)

if %COUNT% EQU 0 (
    echo ERROR: No .bin files found in bin\ or current directory.
    pause
    exit /b 1
)

if "%FAST_MODE%"=="1" (
    echo Found %COUNT% priority bin payloads.
) else (
    echo Found %COUNT% bin payloads \(full scan\).
)
echo.

set /a IDX=1
:loop
if !IDX! GTR %COUNT% (
    echo.
    echo [*] No working bin selected from this pass.
    if "!FAST_MODE!"=="1" (
        choice /c YN /n /m "Run full scan of all bins now? Y/N: "
        if errorlevel 2 goto done
        if errorlevel 1 (
            set "FAST_MODE=0"
            set /a COUNT=0
            for %%F in ("%BIN_DIR%\*.bin") do call :add_bin_if_exists "%%~fF"
            if !COUNT! EQU 0 goto done
            echo.
            echo [*] Full scan enabled. Found !COUNT! bin payloads.
            set /a IDX=1
            goto loop
        )
    )
    echo [*] You can rerun this script.
    goto done
)

set "PAYLOAD=!BIN[%IDX%]!"
echo ==========================================
echo [*] Testing !IDX!/%COUNT%
echo [*] Payload: !PAYLOAD!
echo ==========================================

taskkill /f /im winws.exe >nul 2>&1
timeout /t 1 /nobreak >nul

start "winws-bin-test" /min "%~dp0winws.exe" ^
    --wf-tcp=80,443,2053,2083,2087,2096,8443,%GameFilterTCP% ^
    --wf-udp=443,19294-19344,50000-50100,%GameFilterUDP% ^
    --filter-tcp=443 ^
    --hostlist=%RH1% ^
    --hostlist=%RH2% ^
    --dpi-desync=disorder ^
    --dpi-desync-split-pos=1,2,3 ^
    --dpi-desync-ttl=2 ^
    --dpi-desync-fooling=badsum,badseq ^
    --dpi-desync-repeats=4 ^
    --new ^
    --filter-udp=443 ^
    --hostlist=%RH1% ^
    --hostlist=%RH2% ^
    --dpi-desync=fake ^
    --dpi-desync-repeats=6 ^
    --dpi-desync-cutoff=n2 ^
    --new ^
    --filter-udp=%GameFilterUDP% ^
    --ipset=%RI1% ^
    --ipset=%RI2% ^
    --dpi-desync=fake ^
    --dpi-desync-repeats=12 ^
    --dpi-desync-any-protocol=1 ^
    --dpi-desync-fake-unknown-udp="@!PAYLOAD!" ^
    --dpi-desync-cutoff=n2 ^
    --new ^
    --filter-tcp=%GameFilterTCP% ^
    --ipset=%RI1% ^
    --ipset=%RI2% ^
    --dpi-desync=syndata

echo.
echo Test Roblox: start launcher and join place.
echo.
choice /c YNQ /n /m "Y=works/save  N=next bin  Q=quit: "
if errorlevel 3 goto quit
if errorlevel 2 goto next
if errorlevel 1 goto save

:next
set /a IDX+=1
goto loop

:save
> selected_bin.txt echo !PAYLOAD!
echo.
echo [OK] Saved selected bin to selected_bin.txt
echo [OK] zapret_strong.bat will use it automatically.
goto done

:quit
echo.
echo [*] Stopped by user.

:done
taskkill /f /im winws.exe >nul 2>&1
echo.
echo [*] Finished.
pause
exit /b 0

:add_bin_if_exists
if not exist "%~1" goto :eof
set /a COUNT+=1
set "BIN[%COUNT%]=%~f1"
goto :eof
