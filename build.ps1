# dPI-Bypass Build Script (PowerShell)
$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "dPI-Bypass Build Script" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectDir

Write-Host "Project directory: $ProjectDir"

# Create output directory
if (-not (Test-Path "bin")) {
    New-Item -ItemType Directory -Path "bin" | Out-Null
}

# Function to find compiler
function Find-Compiler {
    # Check PATH
    $gcc = Get-Command g++ -ErrorAction SilentlyContinue
    if ($gcc) {
        return @{ Type = "MinGW"; Path = $gcc.Source }
    }
    
    $cl = Get-Command cl -ErrorAction SilentlyContinue
    if ($cl) {
        return @{ Type = "MSVC"; Path = $cl.Source }
    }
    
    # Check common MinGW locations
    $mingwPaths = @(
        "C:\mingw64\bin\g++.exe",
        "C:\msys64\mingw64\bin\g++.exe",
        "$env:LOCALAPPDATA\Programs\mingw64\bin\g++.exe",
        "C:\ProgramData\chocolatey\lib\mingw\tools\install\mingw64\bin\g++.exe"
    )
    
    foreach ($path in $mingwPaths) {
        if (Test-Path $path) {
            $env:PATH = "$([System.IO.Path]::GetDirectoryName($path));$env:PATH"
            return @{ Type = "MinGW"; Path = $path }
        }
    }
    
    # Check Visual Studio
    $vsPaths = @(
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    )
    
    foreach ($path in $vsPaths) {
        if (Test-Path $path) {
            Write-Host "Found Visual Studio at: $path"
            & cmd /c "`"$path`" && set" | ForEach-Object {
                if ($_ -match "^(.*?)=(.*)$") {
                    [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
                }
            }
            return @{ Type = "MSVC"; Path = "cl.exe" }
        }
    }
    
    return $null
}

$compiler = Find-Compiler

if (-not $compiler) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "ERROR: No C++ compiler found!" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install one of the following:"
    Write-Host ""
    Write-Host "OPTION 1: MinGW-w64 (Recommended)" -ForegroundColor Yellow
    Write-Host "  winget install MinGW.MinGW"
    Write-Host "  Or download from: https://winlibs.com/"
    Write-Host ""
    Write-Host "OPTION 2: Visual Studio Build Tools" -ForegroundColor Yellow
    Write-Host "  winget install Microsoft.VisualStudio.2022.BuildTools --override `"--add Microsoft.VisualStudio.Workload.VCTools`""
    Write-Host ""
    Write-Host "After installation, restart this script."
    exit 1
}

Write-Host "Found compiler: $($compiler.Type) at $($compiler.Path)" -ForegroundColor Green

# Build
if ($compiler.Type -eq "MSVC") {
    Write-Host ""
    Write-Host "Building with MSVC..." -ForegroundColor Cyan
    
    $args = @(
        "/nologo", "/O2", "/W4",
        "/DWIN32_LEAN_AND_MEAN", "/D_CRT_SECURE_NO_WARNINGS",
        "/std:c++17", "/EHsc",
        "/I$ProjectDir",
        "main.cpp", "packet_engine.cpp", "desync_strategies.cpp", "utils.cpp", "roblox_optimizer.cpp",
        "/link", "/OUT:bin\dpi-bypass.exe",
        "/LIBPATH:$ProjectDir",
        "WinDivert.lib", "ws2_32.lib", "iphlpapi.lib"
    )
    
    & cl.exe @args
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "Building with MinGW..." -ForegroundColor Cyan
    
    $args = @(
        "-O2", "-Wall", "-std=c++17",
        "-DWIN32_LEAN_AND_MEAN", "-D_CRT_SECURE_NO_WARNINGS", "-D_WIN32_WINNT=0x0600",
        "-I$ProjectDir",
        "main.cpp", "packet_engine.cpp", "desync_strategies.cpp", "utils.cpp", "roblox_optimizer.cpp",
        "-o", "bin\dpi-bypass.exe",
        "-L$ProjectDir",
        "-lWinDivert", "-lws2_32", "-liphlpapi",
        "-static-libgcc", "-static-libstdc++"
    )
    
    & g++.exe @args
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed!" -ForegroundColor Red
        exit 1
    }
}

# Copy dependencies
Write-Host ""
Write-Host "Copying WinDivert dependencies..." -ForegroundColor Cyan
Copy-Item "$ProjectDir\WinDivert.dll" "bin\" -Force
Copy-Item "$ProjectDir\WinDivert64.sys" "bin\" -Force

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "Build successful!" -ForegroundColor Green
Write-Host "Output: bin\dpi-bypass.exe" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Usage (run as Administrator):" -ForegroundColor Yellow
Write-Host "  .\bin\dpi-bypass.exe roblox"
Write-Host "  .\bin\dpi-bypass.exe youtube"
Write-Host "  .\bin\dpi-bypass.exe discord"
Write-Host ""

