@echo off
chcp 65001 >nul
echo ==========================================
echo ZAPRET2 Build Script (February 2026)
echo ==========================================

set "PROJECT_DIR=%~dp0"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
echo Project folder: %PROJECT_DIR%

if not exist "%PROJECT_DIR%\WinDivert.dll" (
    echo ERROR: WinDivert.dll not found!
    exit /b 1
)

if not exist "%PROJECT_DIR%\WinDivert.lib" (
    echo ERROR: WinDivert.lib not found!
    exit /b 1
)

echo WinDivert SDK found

if not exist "%PROJECT_DIR%\bin" mkdir "%PROJECT_DIR%\bin"

where cl >nul 2>&1
if %errorlevel% == 0 goto :msvc_build

where g++ >nul 2>&1
if %errorlevel% == 0 goto :mingw_build

echo ERROR: No C++ compiler found!
exit /b 1

:msvc_build
echo.
echo Building ZAPRET2 with MSVC...
cl.exe /nologo /O2 /W4 /DWIN32_LEAN_AND_MEAN /D_CRT_SECURE_NO_WARNINGS /std:c++17 /EHsc /I"%PROJECT_DIR%" zapret_main.cpp zapret_engine.cpp utils.cpp /link /OUT:bin\zapret2.exe /LIBPATH:"%PROJECT_DIR%" WinDivert.lib ws2_32.lib iphlpapi.lib
if %errorlevel% neq 0 goto :build_failed
goto :copy_files

:mingw_build
echo.
echo Building ZAPRET2 with MinGW...
g++.exe -O2 -Wall -std=c++17 -DWIN32_LEAN_AND_MEAN -D_CRT_SECURE_NO_WARNINGS -D_WIN32_WINNT=0x0600 -I"%PROJECT_DIR%" zapret_main.cpp zapret_engine.cpp utils.cpp -o bin\zapret2.exe -L"%PROJECT_DIR%" -lWinDivert -lws2_32 -liphlpapi -static-libgcc -static-libstdc++
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
echo Build successful! bin\zapret2.exe
echo ==========================================
echo.
echo Usage: bin\zapret2.exe roblox
echo        bin\zapret2.exe youtube
echo        bin\zapret2.exe discord
echo        bin\zapret2.exe all -v --stats
echo.
exit /b 0
