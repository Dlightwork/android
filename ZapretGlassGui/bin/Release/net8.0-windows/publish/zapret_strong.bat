@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - STRONG MODE
echo winws2 + Lua preset mode
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator rights...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','\"%~f0\"' -Verb RunAs" >nul 2>&1
    exit /b 0
)

cd /d "%~dp0"
setlocal EnableExtensions EnableDelayedExpansion

set "ENGINE=winws2.exe"
set "RUNNER=tools\run-winws2-preset.ps1"
set "BASE_PRESET=presets\all_tcp_udp_multisplit_sni.args"
set "APPEND_PRESET=%TEMP%\zapret_strong_append_%RANDOM%%RANDOM%.args"

if not exist "%ENGINE%" (
    echo ERROR: %ENGINE% not found
    pause
    exit /b 1
)
if not exist "%RUNNER%" (
    echo ERROR: %RUNNER% not found
    pause
    exit /b 1
)
if not exist "%BASE_PRESET%" (
    echo ERROR: %BASE_PRESET% not found
    pause
    exit /b 1
)

set "ROBLOX_HOSTLIST=lists\list-roblox.txt"
if not exist "%ROBLOX_HOSTLIST%" set "ROBLOX_HOSTLIST=list-roblox.txt"
if not exist "%ROBLOX_HOSTLIST%" set "ROBLOX_HOSTLIST=lists\roblox_domains.txt"
if not exist "%ROBLOX_HOSTLIST%" set "ROBLOX_HOSTLIST=roblox_domains.txt"

set "ROBLOX_IPSET=lists\ipset-roblox.txt"
if not exist "%ROBLOX_IPSET%" set "ROBLOX_IPSET=ipset-roblox.txt"
if not exist "%ROBLOX_IPSET%" set "ROBLOX_IPSET=lists\roblox_ips.txt"
if not exist "%ROBLOX_IPSET%" set "ROBLOX_IPSET=roblox_ips.txt"

set "AUTO_HOST=lists\_auto_hostlist.txt"
set "AUTO_IP=lists\_auto_ipset.txt"
set /a AUTO_HOST_FILES=0
set /a AUTO_IP_FILES=0
call :build_auto_lists "%AUTO_HOST%" "%AUTO_IP%"
if exist "%AUTO_HOST%" for %%A in ("%AUTO_HOST%") do if %%~zA GTR 0 set "ROBLOX_HOSTLIST=%AUTO_HOST%"
if exist "%AUTO_IP%" for %%A in ("%AUTO_IP%") do if %%~zA GTR 0 set "ROBLOX_IPSET=%AUTO_IP%"

set "ROBLOX_ENABLED=0"
if exist "%ROBLOX_HOSTLIST%" if exist "%ROBLOX_IPSET%" set "ROBLOX_ENABLED=1"

> "%APPEND_PRESET%" (
    echo --new
    echo --filter-udp=49152-65535
    if "%ROBLOX_ENABLED%"=="1" echo --hostlist=%ROBLOX_HOSTLIST%
    if "%ROBLOX_ENABLED%"=="1" echo --ipset=%ROBLOX_IPSET%
    echo --out-range=-d10
    echo --payload=all
    echo --lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=12
    echo --new
    echo --filter-udp=49152-65535
    if "%ROBLOX_ENABLED%"=="1" echo --ipset=%ROBLOX_IPSET%
    echo --out-range=-d10
    echo --payload=all
    echo --lua-desync=fake:blob=fake_quic:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=12
    echo --new
    echo --filter-tcp=443,1024-65535
    if "%ROBLOX_ENABLED%"=="1" echo --hostlist=%ROBLOX_HOSTLIST%
    if "%ROBLOX_ENABLED%"=="1" echo --ipset=%ROBLOX_IPSET%
    echo --out-range=-d8
    echo --lua-desync=send:repeats=2
    echo --lua-desync=syndata:blob=tls_google
    echo --lua-desync=tls_multisplit_sni:seqovl=652:seqovl_pattern=tls_google
)

echo.
echo [*] Stopping old processes...
taskkill /f /im winws2.exe >nul 2>&1
taskkill /f /im winws.exe >nul 2>&1
timeout /t 1 /nobreak >nul

echo.
echo [*] Engine: %ENGINE%
echo [*] Base preset: %BASE_PRESET%
if "%ROBLOX_ENABLED%"=="1" (
    echo [*] Lists mode: ON
    echo [*] Hostlist: %ROBLOX_HOSTLIST%
    echo [*] IP set:   %ROBLOX_IPSET%
    echo [*] Auto TXT included: hostlist=!AUTO_HOST_FILES! ipset=!AUTO_IP_FILES!
) else (
    echo [*] Lists mode: OFF (hostlist/ipset not found)
)
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%RUNNER%" -EnginePath "%ENGINE%" -BaseDir "%cd%" -PresetFile "%BASE_PRESET%;%APPEND_PRESET%"
set "RC=%ERRORLEVEL%"

del "%APPEND_PRESET%" >nul 2>&1

echo.
if not "%RC%"=="0" echo [!] Process exited with code %RC%
echo [*] Strong profile stopped
pause
exit /b %RC%

:build_auto_lists
set "AUTO_HOST_FILE=%~1"
set "AUTO_IP_FILE=%~2"
if not defined AUTO_HOST_FILE goto :eof
if not defined AUTO_IP_FILE goto :eof

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
