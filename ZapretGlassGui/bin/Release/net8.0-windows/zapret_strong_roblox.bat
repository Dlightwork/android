@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - STRONG MODE (Roblox)
echo Targeted High Ports Profile (1024-65535)
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

cd /d "%~dp0"
setlocal EnableExtensions EnableDelayedExpansion

rem ---------------------------------------------------------------------------
rem  Determine Roblox hostlist and ipset files.  When available, build unified
rem  auto lists from all .txt files under the lists directory so users do not
rem  need to manually merge them.  If a roblox-cidr.txt file is found (either
rem  in the current directory or the lists folder) it will override the default
rem  ipset.  Otherwise, fall back to ipset-roblox.txt or roblox_ips.txt.
rem ---------------------------------------------------------------------------

set "GameFilter=1024-65535"

rem default hostlist/ipset filenames
set "ROBLOX_HOSTLIST=list-roblox.txt"
set "ROBLOX_IPSET=ipset-roblox.txt"

rem if roblox-cidr.txt exists in lists or current directory, prefer it
if exist "lists\roblox-cidr.txt" set "ROBLOX_IPSET=lists\roblox-cidr.txt"
if exist "roblox-cidr.txt" set "ROBLOX_IPSET=roblox-cidr.txt"

rem fallback to legacy files if defaults are missing
if not exist "%ROBLOX_HOSTLIST%" set "ROBLOX_HOSTLIST=roblox_domains.txt"
if not exist "%ROBLOX_IPSET%" set "ROBLOX_IPSET=roblox_ips.txt"

rem ---------------------------------------------------------------------------
rem  Build auto lists by concatenating all .txt files in the lists directory
rem  excluding reserved names.  If the resulting files are non-empty, use them
rem  as the Roblox hostlist and ipset so the user can place additional lists
rem  into the lists folder without editing the batch file.
rem ---------------------------------------------------------------------------
set "AUTO_HOST=lists\_auto_hostlist.txt"
set "AUTO_IP=lists\_auto_ipset.txt"
set /a AUTO_HOST_FILES=0
set /a AUTO_IP_FILES=0
call :build_auto_lists "%AUTO_HOST%" "%AUTO_IP%"
if exist "%AUTO_HOST%" for %%A in ("%AUTO_HOST%") do if %%~zA GTR 0 (
    set "ROBLOX_HOSTLIST=%AUTO_HOST%"
)
if exist "%AUTO_IP%" for %%A in ("%AUTO_IP%") do if %%~zA GTR 0 (
    set "ROBLOX_IPSET=%AUTO_IP%"
)

echo.
echo [*] Stopping old winws instances...
taskkill /f /im winws.exe >nul 2>&1
timeout /t 1 /nobreak >nul

echo.
echo [*] Starting STRONG bypass for Roblox .exe (targeted mode)...
echo [*] Profile 1: TCP 443 by hostlist (launcher/auth)
echo [*] Profile 2: UDP 443 by hostlist (QUIC bootstrap)
echo [*] Profile 3: UDP 1024-65535 by IP set (any protocol)
echo [*] Profile 4: TCP 1024-65535 by IP set
echo [*] Hostlist: %ROBLOX_HOSTLIST%
echo [*] IP set:   %ROBLOX_IPSET%
echo.

winws.exe ^
    --wf-tcp=80,443,2053,2083,2087,2096,8443,%GameFilter% ^
    --wf-udp=443,19294-19344,50000-50100,%GameFilter% ^
    --filter-tcp=443 ^
    --hostlist=%ROBLOX_HOSTLIST% ^
    --dpi-desync=disorder ^
    --dpi-desync-split-pos=1,2,3 ^
    --dpi-desync-ttl=2 ^
    --dpi-desync-fooling=badsum,badseq ^
    --dpi-desync-repeats=5 ^
    --new ^
    --filter-udp=443 ^
    --hostlist=%ROBLOX_HOSTLIST% ^
    --dpi-desync=fake ^
    --dpi-desync-repeats=6 ^
    --new ^
    --filter-udp=%GameFilter% ^
    --ipset=%ROBLOX_IPSET% ^
    --dpi-desync=fake ^
    --dpi-desync-repeats=12 ^
    --dpi-desync-any-protocol=1 ^
    --dpi-desync-fake-unknown-udp=quic_initial_www_google_com.bin ^
    --dpi-desync-cutoff=n3 ^
    --new ^
    --filter-tcp=%GameFilter% ^
    --ipset=%ROBLOX_IPSET% ^
    --dpi-desync=syndata

echo.
echo [*] Strong bypass for Roblox stopped
pause

goto :eof

rem ===========================================================================
rem  build_auto_lists
rem  Concatenate every .txt file from the lists directory (and current dir) into
rem  a unified hostlist and ipset.  Skips reserved names and avoids duplicate
rem  entries when the same filename exists in both places.  This function is
rem  adapted from zapret_strong.bat to provide automatic list management for
rem  Roblox mode.
rem ===========================================================================
:build_auto_lists
set "AUTO_HOST_FILE=%~1"
set "AUTO_IP_FILE=%~2"
if not defined AUTO_HOST_FILE goto :eof
if not defined AUTO_IP_FILE goto :eof

rem Create/empty the output files
type nul > "%AUTO_HOST_FILE%"
type nul > "%AUTO_IP_FILE%"

for %%D in ("lists" ".") do (
    if exist "%%~D\*.txt" (
        for %%F in ("%%~D\*.txt") do (
            set "NAME=%%~nxF"
            set "STEM=%%~nF"
            set "FROM_DIR=%%~D"
            call :should_skip_txt "!NAME!"
            rem Skip duplicates: if the file exists in lists and we're in root dir
            if /i "!FROM_DIR!"=="." if exist "lists\!NAME!" set "SKIP_TXT=1"
            if "!SKIP_TXT!"=="0" (
                set "IS_IP=0"
                if /i "!STEM:ipset=!" NEQ "!STEM!" set "IS_IP=1"
                if /i "!STEM:_ips=!" NEQ "!STEM!" set "IS_IP=1"
                if "!IS_IP!"=="1" (
                    >> "%AUTO_IP_FILE%" type "%%~fF"
                    >> "%AUTO_IP_FILE%" echo.
                    set /a AUTO_IP_FILES+=1
                ) else (
                    >> "%AUTO_HOST_FILE%" type "%%~fF"
                    >> "%AUTO_HOST_FILE%" echo.
                    set /a AUTO_HOST_FILES+=1
                )
            )
        )
    )
)
goto :eof

:should_skip_txt
set "SKIP_TXT=0"
if /i "%~1"=="selected_bin.txt" set "SKIP_TXT=1"
if /i "%~1"=="test_out.txt" set "SKIP_TXT=1"
if /i "%~1"=="error.txt" set "SKIP_TXT=1"
if /i "%~1"=="help.txt" set "SKIP_TXT=1"
if /i "%~1"=="CMakeLists.txt" set "SKIP_TXT=1"
if /i "%~1"=="service_config.txt" set "SKIP_TXT=1"
if /i "%~1"=="_auto_hostlist.txt" set "SKIP_TXT=1"
if /i "%~1"=="_auto_ipset.txt" set "SKIP_TXT=1"
goto :eof
