@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET - ALL TCP & UDP multisplit_sni
echo winws2 + Lua preset mode
echo ==========================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator rights...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','\"%~f0\"' -Verb RunAs" >nul 2>&1
    exit /b 0
)

cd /d "%~dp0"
setlocal EnableExtensions

set "ENGINE=winws2.exe"
set "RUNNER=tools\run-winws2-preset.ps1"
set "BASE_PRESET=presets\all_tcp_udp_multisplit_sni.args"
set "APPEND_PRESET="

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

set "ROBLOX_ENABLED=0"
if exist "%ROBLOX_HOSTLIST%" if exist "%ROBLOX_IPSET%" set "ROBLOX_ENABLED=1"

if "%ROBLOX_ENABLED%"=="1" (
    set "APPEND_PRESET=%TEMP%\zapret_multisplit_append_%RANDOM%%RANDOM%.args"
    > "%APPEND_PRESET%" (
        echo --new
        echo --filter-udp=49152-65535
        echo --hostlist=%ROBLOX_HOSTLIST%
        echo --ipset=%ROBLOX_IPSET%
        echo --out-range=-d8
        echo --payload=all
        echo --lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=10
    )
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
    echo [*] Roblox supplement: ON
    echo [*] Roblox hostlist: %ROBLOX_HOSTLIST%
    echo [*] Roblox ipset:    %ROBLOX_IPSET%
) else (
    echo [*] Roblox supplement: OFF (hostlist/ipset not found)
)
echo.

if defined APPEND_PRESET (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%RUNNER%" -EnginePath "%ENGINE%" -BaseDir "%cd%" -PresetFile "%BASE_PRESET%;%APPEND_PRESET%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%RUNNER%" -EnginePath "%ENGINE%" -BaseDir "%cd%" -PresetFile "%BASE_PRESET%"
)
set "RC=%ERRORLEVEL%"

if defined APPEND_PRESET del "%APPEND_PRESET%" >nul 2>&1

echo.
if not "%RC%"=="0" echo [!] Process exited with code %RC%
echo [*] Profile stopped
pause
exit /b %RC%
