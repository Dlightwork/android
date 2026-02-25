@echo off
chcp 65001 >nul
cd /d "%~dp0"
setlocal EnableExtensions

set "GUI_PROJECT=ZapretGlassGui\ZapretGlassGui.csproj"
set "GUI_EXE=ZapretGlassGui\bin\Release\net8.0-windows\NoRKN.exe"

if not exist "%GUI_PROJECT%" (
    echo ERROR: %GUI_PROJECT% not found
    pause
    exit /b 1
)

set "FORCE_BUILD=0"
if /I "%~1"=="--build" set "FORCE_BUILD=1"

if not exist "%GUI_EXE%" set "FORCE_BUILD=1"

if "%FORCE_BUILD%"=="1" (
    echo [*] Building .NET GUI...
    dotnet build "%GUI_PROJECT%" -c Release -v minimal
    if errorlevel 1 (
        echo [!] Build failed
        pause
        exit /b 1
    )
)

echo [*] Starting NoRKN...
"%GUI_EXE%"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo [!] GUI exited with code %RC%
    pause
)

exit /b %RC%
