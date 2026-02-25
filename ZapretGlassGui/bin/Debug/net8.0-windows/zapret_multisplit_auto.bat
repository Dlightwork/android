@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - MULTISPLIT SNI MODE (Auto lists)
echo TCP + UDP with multisplit SNI
echo ==========================================

rem Require administrator rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Run as Administrator!
    pause
    exit /b 1
)

rem Change to the script directory
cd /d "%~dp0"

rem Initialise variables and enable delayed expansion
setlocal EnableExtensions EnableDelayedExpansion

rem Define catch‑all port ranges for both TCP and UDP. Roblox support states that the
rem client uses UDP ports 49152‑65535【417083560409813†L93-L97】, but many other services
rem operate over ports 80 and 443. To ensure stable access to all services, we
rem intercept 80 and 443 up through 65535 on both protocols.
set "GameFilterTCP=80,443-65535"
set "GameFilterUDP=80,443-65535"

rem Default host and ipset files. For all‑service mode we use the combined
rem all_services.txt hostlist and ipset‑all.txt (if present). These files come
rem from the `lists` directory. They can be overridden by auto‑generated lists.
set "RH1=lists\all_services.txt"
set "RH2=lists\all_services.txt"
set "RI1=lists\ipset-all.txt"
set "RI2=lists\ipset-all.txt"

rem If default files are missing in lists, fall back to files in the root folder
if not exist "%RH1%" set "RH1=all_services.txt"
if not exist "%RH2%" set "RH2=%RH1%"
if not exist "%RI1%" set "RI1=ipset-all.txt"
if not exist "%RI2%" set "RI2=%RI1%"

rem Paths to auto‑generated files
set "AUTO_HOST=lists\_auto_hostlist.txt"
set "AUTO_IP=lists\_auto_ipset.txt"
set /a AUTO_HOST_FILES=0
set /a AUTO_IP_FILES=0
call :build_auto_lists "%AUTO_HOST%" "%AUTO_IP%"

rem If auto hostlist exists and is non‑empty, use it instead of defaults
if exist "%AUTO_HOST%" for %%A in ("%AUTO_HOST%") do if %%~zA gtr 0 (
    set "RH1=%AUTO_HOST%"
    set "RH2=%AUTO_HOST%"
)

rem If auto ipset exists and is non‑empty, use it instead of defaults
if exist "%AUTO_IP%" for %%A in ("%AUTO_IP%") do if %%~zA gtr 0 (
    set "RI1=%AUTO_IP%"
    set "RI2=%AUTO_IP%"
)

echo.
echo [*] Starting MULTISPLIT SNI bypass (Auto)...
echo [*] All TCP and UDP traffic will be intercepted
echo [*] Hostlist: %RH1%
echo [*] IPSet:   %RI1%
echo [*] Auto TXT included: hostlist=!AUTO_HOST_FILES! ipset=!AUTO_IP_FILES!
echo.

rem Terminate any existing winws process before launching a new one
taskkill /f /im winws.exe >nul 2>&1
timeout /t 1 /nobreak >nul

rem Launch winws with multisplit SNI strategies. We use three strategies:
rem 1) A multisplit disorder for TCP on all ports to split the TLS ClientHello
rem    across multiple segments and confuse DPI. We apply several split
rem    positions and TTL values similar to zapret2 preset.
rem 2) A secondary split only for port 443 to ensure HTTPS handshake splitting.
rem 3) For UDP traffic we send fake packets to break DPI state on protocols
rem    like QUIC. We exclude Russian IP subnets via ipset-exclude (if file exists).
rem 4) Finally we append a SYN data desync on all TCP ports with the ipset list
rem    to further protect against DPI state tracking.

winws.exe ^
    --wf-tcp=%GameFilterTCP% ^
    --wf-udp=%GameFilterUDP% ^
    --ipset-exclude=lists/ipset-ru.txt ^
    --filter-tcp=%GameFilterTCP% ^
    --hostlist=%RH1% ^
    --hostlist=%RH2% ^
    --dpi-desync=disorder ^
    --dpi-desync-split-pos=1,2,3,4,5 ^
    --dpi-desync-ttl=2 ^
    --dpi-desync-fooling=badsum,badseq,md5sig ^
    --dpi-desync-repeats=7 ^
    --new ^
    --filter-tcp=443 ^
    --hostlist=%RH1% ^
    --hostlist=%RH2% ^
    --dpi-desync=split ^
    --dpi-desync-split-pos=1,2,4,8 ^
    --dpi-desync-ttl=3 ^
    --dpi-desync-fooling=badsum ^
    --dpi-desync-repeats=5 ^
    --new ^
    --filter-udp=%GameFilterUDP% ^
    --hostlist=%RH1% ^
    --hostlist=%RH2% ^
    --dpi-desync=fake ^
    --dpi-desync-ttl=2 ^
    --dpi-desync-fooling=badseq ^
    --dpi-desync-repeats=10 ^
    --new ^
    --filter-tcp=%GameFilterTCP% ^
    --ipset=%RI1% ^
    --ipset=%RI2% ^
    --dpi-desync=syndata ^
    --new ^
    --filter-tcp=%GameFilterTCP% ^
    --dpi-desync=syndata

echo.
echo [*] Multisplit SNI auto bypass stopped
pause
exit /b 0

rem --------------------
rem Build auto hostlist and ipset from all .txt files in lists and current dir
rem This function is borrowed from zapret_strong.bat to unify behaviour across
rem modes. It concatenates files ending with ipset/_ips to the ipset file and
rem other .txt files to the hostlist. Some filenames are skipped to avoid
rem duplicates or service files.
:build_auto_lists
set "AUTO_HOST_FILE=%~1"
set "AUTO_IP_FILE=%~2"
if not defined AUTO_HOST_FILE goto :eof
if not defined AUTO_IP_FILE goto :eof

rem Empty files before appending
type nul > "%AUTO_HOST_FILE%"
type nul > "%AUTO_IP_FILE%"

for %%D in ("lists" ".") do (
    if exist "%%~D\*.txt" (
        for %%F in ("%%~D\*.txt") do (
            set "NAME=%%~nxF"
            set "STEM=%%~nF"
            set "FROM_DIR=%%~D"
            call :should_skip_txt "!NAME!"
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

rem Decide whether to skip a given filename when building auto lists
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