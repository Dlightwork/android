#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Build NoRKN Windows installer using Inno Setup
    
.DESCRIPTION
    Builds the NoRKN Windows application and packages it into an installer
    using Inno Setup. Requires Inno Setup to be installed.
    
.PARAMETER Configuration
    Build configuration: Debug or Release (default: Release)
    
.PARAMETER BuildApp
    Build the C# application before creating installer (default: true)
    
.PARAMETER InnoSetupPath
    Path to Inno Setup compiler (auto-detect by default)
    
.EXAMPLE
    .\build-windows-installer.ps1 -Configuration Release
    
.EXAMPLE
    .\build-windows-installer.ps1 -Configuration Release -BuildApp $true
#>

param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    
    [bool]$BuildApp = $true,
    
    [string]$InnoSetupPath = ""
)

$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommandPath
$GuiProject = Join-Path $ProjectRoot "ZapretGlassGui"
$GuiCsproj = Join-Path $GuiProject "ZapretGlassGui.csproj"

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         NoRKN Windows Installer Builder v2.0             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Step 1: Find Inno Setup compiler
if ([string]::IsNullOrWhiteSpace($InnoSetupPath)) {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "Step 1: Locating Inno Setup Compiler" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
    
    $commonPaths = @(
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 5\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 5\ISCC.exe"
    )
    
    $InnoSetupPath = $null
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $InnoSetupPath = $path
            Write-Host "✓ Found Inno Setup: $InnoSetupPath" -ForegroundColor Green
            break
        }
    }
    
    if (!$InnoSetupPath) {
        Write-Host "⚠ Inno Setup not found in common locations" -ForegroundColor Yellow
        Write-Host "Download and install from: https://jrsoftware.org/isdl.php`n" -ForegroundColor Yellow
        
        $InnoSetupPath = Read-Host "Enter path to ISCC.exe"
        
        if (!(Test-Path $InnoSetupPath)) {
            Write-Error "Inno Setup compiler not found at: $InnoSetupPath"
            exit 1
        }
    }
} else {
    if (!(Test-Path $InnoSetupPath)) {
        Write-Error "Inno Setup compiler not found at: $InnoSetupPath"
        exit 1
    }
}

# Step 2: Build the application
if ($BuildApp) {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "Step 2: Building NoRKN Application" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
    
    # Check .NET SDK
    try {
        $dotnetVersion = dotnet --version
        Write-Host "✓ .NET SDK: $dotnetVersion" -ForegroundColor Green
    } catch {
        Write-Error ".NET SDK not found. Install from: https://dotnet.microsoft.com/download/dotnet/8.0"
        exit 1
    }
    
    # Restore dependencies
    Write-Host "`nRestoring dependencies..."
    try {
        & dotnet restore $GuiCsproj --verbosity minimal
        Write-Host "✓ Dependencies restored" -ForegroundColor Green
    } catch {
        Write-Error "Failed to restore dependencies: $_"
        exit 1
    }
    
    # Build
    Write-Host "`nBuilding $Configuration configuration..."
    try {
        & dotnet build $GuiCsproj `
            -c $Configuration `
            -f net8.0-windows `
            --no-restore `
            --verbosity minimal
        Write-Host "✓ Build completed" -ForegroundColor Green
    } catch {
        Write-Error "Failed to build application: $_"
        exit 1
    }
    
    # Publish for distribution
    Write-Host "`nPublishing for distribution..."
    try {
        & dotnet publish $GuiCsproj `
            -c $Configuration `
            -f net8.0-windows `
            --no-restore `
            --self-contained `
            --runtime win-x64 `
            --verbosity minimal `
            -p:PublishSingleFile=false `
            -p:PublishTrimmed=false `
            -p:PublishReadyToRun=false
        Write-Host "✓ Application published" -ForegroundColor Green
    } catch {
        Write-Error "Failed to publish application: $_"
        exit 1
    }
}

# Step 3: Prepare installer configuration
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Step 3: Preparing Installer Script" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

$ issFile = Join-Path $ProjectRoot "norkn-installer.iss"
if (!(Test-Path $issFile)) {
    Write-Error "Installer script not found: $issFile"
    exit 1
}

Write-Host "✓ Installer script found: $issFile" -ForegroundColor Green

# Step 4: Create output directory
$outputDir = Join-Path $ProjectRoot "dist\installer"
$null = New-Item -ItemType Directory -Path $outputDir -Force

Write-Host "✓ Output directory: $outputDir" -ForegroundColor Green

# Step 5: Build installer
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Step 4: Creating Installer with Inno Setup" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

try {
    $isccOutput = & $InnoSetupPath $issFile 2>&1
    Write-Host $isccOutput
    
    # Check if compilation was successful
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Inno Setup compilation failed with code: $LASTEXITCODE"
        exit 1
    }
    
    Write-Host "`n✓ Installer created successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to compile installer: $_"
    exit 1
}

# Step 6: Verify installer
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Step 5: Verifying Installer" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

$installerFile = Get-ChildItem -Path $outputDir -Filter "NoRKN-Setup-*.exe" -ErrorAction SilentlyContinue | 
                 Sort-Object LastWriteTime -Descending | 
                 Select-Object -First 1

if ($installerFile) {
    $sizeInMB = [Math]::Round($installerFile.Length / 1MB, 2)
    Write-Host "✓ Installer: $($installerFile.Name)" -ForegroundColor Green
    Write-Host "  Size: $sizeInMB MB" -ForegroundColor Gray
    Write-Host "  Path: $($installerFile.FullName)" -ForegroundColor Gray
    
    # Optional: Show additional info
    $fileInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($installerFile.FullName)
    if ($fileInfo.FileVersion) {
        Write-Host "  Version: $($fileInfo.FileVersion)" -ForegroundColor Gray
    }
} else {
    Write-Error "Installer file not found in output directory"
    exit 1
}

# Final summary
Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    BUILD SUCCESSFUL ✓                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Installer ready for distribution:" -ForegroundColor Green
Write-Host "  🔹 Location: $($installerFile.FullName)" -ForegroundColor Cyan
Write-Host "  🔹 Size: $sizeInMB MB" -ForegroundColor Cyan

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. Test the installer on a clean Windows system" -ForegroundColor Gray
Write-Host "  2. Verify WinDivert driver installation" -ForegroundColor Gray
Write-Host "  3. Test all application features" -ForegroundColor Gray
Write-Host "  4. Sign the installer (optional, for Windows SmartScreen)" -ForegroundColor Gray

Write-Host "`nTo sign the installer with a certificate:" -ForegroundColor Yellow
Write-Host '  signtool sign /f "path\to\certificate.pfx" /p "password" /t "http://timestamp.server" `' -ForegroundColor Gray
Write-Host '    "$($installerFile.FullName)"' -ForegroundColor Gray

Write-Host ""
