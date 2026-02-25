@echo off
chcp 65001 >nul
echo ==========================================
echo dPI-Bypass Build Script
echo ==========================================

set "PROJECT_DIR=%~dp0"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
echo Project folder: %PROJECT_DIR%

if not exist "%PROJECT_DIR%\WinDivert.dll" (
    echo ERROR: WinDivert.dll not found!
    exit /b 1
)

if not exist "%PROJECT_DIR%\WinDivert.lib" (
    echo.
    echo ==========================================
    echo ERROR: WinDivert.lib not found!
    echo ==========================================
    echo.
    echo Download WinDivert SDK:
    echo   https://reqrypt.org/download/WinDivert-2.2.2-A.zip
    echo.
    exit /b 1
)

echo WinDivert SDK found

if not exist "%PROJECT_DIR%\bin" mkdir "%PROJECT_DIR%\bin"

where cl >nul 2>&1
if %errorlevel% == 0 goto :msvc_build

where g++ >nul 2>&1
if %errorlevel% == 0 goto :mingw_build

if exist "C:\mingw64\bin\g++.exe" (
    set "PATH=C:\mingw64\bin;%PATH%"
    goto :mingw_build
)

if exist "C:\msys64\mingw64\bin\g++.exe" (
    set "PATH=C:\msys64\mingw64\bin;%PATH%"
    goto :mingw_build
)

echo.
echo ERROR: No C++ compiler found!
echo Install MinGW: winget install MinGW.MinGW
echo.
exit /b 1

:msvc_build
echo.
echo Building with MSVC...
cl.exe /nologo /O2 /W4 /DWIN32_LEAN_AND_MEAN /D_CRT_SECURE_NO_WARNINGS /std:c++17 /EHsc /I"%PROJECT_DIR%" main.cpp packet_engine.cpp desync_strategies.cpp utils.cpp roblox_optimizer.cpp /link /OUT:bin\dpi-bypass.exe /LIBPATH:"%PROJECT_DIR%" WinDivert.lib ws2_32.lib iphlpapi.lib
if %errorlevel% neq 0 goto :build_failed
goto :copy_files

:mingw_build
echo.
echo Building with MinGW...
g++.exe -O2 -Wall -std=c++17 -DWIN32_LEAN_AND_MEAN -D_CRT_SECURE_NO_WARNINGS -D_WIN32_WINNT=0x0600 -I"%PROJECT_DIR%" main.cpp packet_engine.cpp desync_strategies.cpp utils.cpp roblox_optimizer.cpp -o bin\dpi-bypass.exe -L"%PROJECT_DIR%" -lWinDivert -lws2_32 -liphlpapi -static-libgcc -static-libstdc++
if %errorlevel% neq 0 goto :build_failed
goto :copy_files

:build_failed
echo Build failed!
exit /b 1

:copy_files
echo.
echo Copying dependencies...
copy /Y "%PROJECT_DIR%\WinDivert.dll" bin\
copy /Y "%PROJECT_DIR%\WinDivert64.sys" bin\
echo.
echo ==========================================
echo Build successful! bin\dpi-bypass.exe
echo ==========================================
echo.
echo Usage: bin\dpi-bypass.exe roblox
echo        bin\dpi-bypass.exe youtube
echo        bin\dpi-bypass.exe discord
echo.
exit /b 0
