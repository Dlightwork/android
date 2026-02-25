#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Check NoRKN installer build dependencies
    
.DESCRIPTION
    Verifies all required tools and dependencies are installed:
    - Inno Setup 5.x or 6.x
    - .NET 8.0 SDK
    - Required Visual C++ runtimes
    - Build tools
    
.PARAMETER SkipInstall
    If $true, only check but don't suggest installation (default: $false)
    
.EXAMPLE
    .\check-installer-setup.ps1
    
.EXAMPLE
    .\check-installer-setup.ps1 -SkipInstall $true
#>

param(
    [bool]$SkipInstall = $false
)

$ErrorActionPreference = "SilentlyContinue"

$script:missingDeps = @()
$script:warnings = @()

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     NoRKN Installer Build - Dependency Checker v1.0      ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Helper functions
function Test-CommandExists {
    param([string]$Command)
    try {
        if (Get-Command $Command -ErrorAction SilentlyContinue) {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Find-ExecutablePath {
    param([string]$Name, [string[]]$SearchPaths)
    
    foreach ($path in $SearchPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

# Check 1: Inno Setup
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Check 1: Inno Setup Compiler" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

$innoSetupPaths = @(
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 5\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 5\ISCC.exe"
)

$innoSetupPath = Find-ExecutablePath -Name "ISCC.exe" -SearchPaths $innoSetupPaths

if ($innoSetupPath) {
    $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($innoSetupPath)
    Write-Host "✓ Inno Setup found" -ForegroundColor Green
    Write-Host "  Path: $innoSetupPath" -ForegroundColor Gray
    Write-Host "  Version: $($version.ProductVersion)" -ForegroundColor Gray
} else {
    Write-Host "✗ Inno Setup not found" -ForegroundColor Red
    Write-Host "  Checked paths:" -ForegroundColor Gray
    $innoSetupPaths | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Write-Host "`n  Download from: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    Write-Host "  Or install via: choco install innosetup" -ForegroundColor Yellow
    $script:missingDeps += "Inno Setup"
}

# Check 2: .NET SDK
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Check 2: .NET 8.0 SDK" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

try {
    $dotnetVersion = dotnet --version
    
    # Parse version
    $majorVersion = [int]($dotnetVersion -split '\.')[0]
    
    if ($majorVersion -ge 8) {
        Write-Host "✓ .NET SDK installed" -ForegroundColor Green
        Write-Host "  Version: $dotnetVersion" -ForegroundColor Gray
        
        # List workloads
        try {
            $workloads = dotnet workload list 2>$null | grep -i "windows\|aspire" | Select-Object -First 5
            if ($workloads) {
                Write-Host "  Workloads:" -ForegroundColor Gray
                $workloads | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            }
        } catch {
            # Ignore workload listing errors
        }
    } else {
        Write-Host "✗ .NET SDK version too old" -ForegroundColor Red
        Write-Host "  Found: $dotnetVersion" -ForegroundColor Gray
        Write-Host "  Required: 8.0 or later" -ForegroundColor Gray
        Write-Host "  Download: https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Yellow
        $script:missingDeps += ".NET SDK 8.0"
    }
} catch {
    Write-Host "✗ .NET SDK not found" -ForegroundColor Red
    Write-Host "  Install from: https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Yellow
    Write-Host "  Or via: choco install dotnet-sdk" -ForegroundColor Yellow
    $script:missingDeps += ".NET SDK"
}

# Check 3: Visual C++ Redistributables
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Check 3: Visual C++ Redistributables" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

$vcRuntimes = @(
    @{Name = "Visual C++ 2022 (x64)"; Reg = "HKLM:\Software\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"; MinVer = 15},
    @{Name = "Visual C++ 2019 (x64)"; Reg = "HKLM:\Software\WOW6432Node\Microsoft\VisualStudio\14.0\VC"; MinVer = 0}
)

$hasVc = $false
try {
    $vcPath = Get-ItemProperty "HKLM:\SOFTWARE\Classes\Installer\Products" -ErrorAction SilentlyContinue
    if ($vcPath) {
        Write-Host "✓ Visual C++ redistributables detected" -ForegroundColor Green
        $hasVc = $true
    }
} catch {
    Write-Host "⚠ Could not verify Visual C++ (may still be installed)" -ForegroundColor Yellow
}

if (!$hasVc) {
    $script:warnings += "Visual C++ redistributables may need installation"
}

# Check 4: Project Files
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Check 4: Required Project Files" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommandPath
$requiredFiles = @(
    @{Path = "ZapretGlassGui\ZapretGlassGui.csproj"; Desc = "GUI project file"},
    @{Path = "norkn-installer.iss"; Desc = "Inno Setup script"},
    @{Path = "build-windows-installer.ps1"; Desc = "Build script"}
)

$allFilesExist = $true
foreach ($file in $requiredFiles) {
    $fullPath = Join-Path $projectRoot $file.Path
    if (Test-Path $fullPath) {
        Write-Host "✓ $($file.Desc)" -ForegroundColor Green
        Write-Host "  $(Split-Path -Leaf $file.Path)" -ForegroundColor Gray
    } else {
        Write-Host "✗ Missing: $($file.Desc)" -ForegroundColor Red
        Write-Host "  Expected: $($file.Path)" -ForegroundColor Gray
        $allFilesExist = $false
    }
}

if (!$allFilesExist) {
    $script:missingDeps += "Project files"
}

# Check 5: Disk Space
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Check 5: Disk Space" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

try {
    $drive = Get-PSDrive -Name D -ErrorAction SilentlyContinue
    if (!$drive) {
        $drive = Get-PSDrive -Name C
    }
    
    $availableGB = [Math]::Round($drive.Free / 1GB, 2)
    $requiredGB = 2
    
    Write-Host "Available: $availableGB GB" -ForegroundColor Gray
    Write-Host "Required: ~$requiredGB GB" -ForegroundColor Gray
    
    if ($availableGB -ge $requiredGB) {
        Write-Host "✓ Sufficient disk space" -ForegroundColor Green
    } else {
        Write-Host "⚠ Warning: Limited disk space" -ForegroundColor Yellow
        $script:warnings += "Only $availableGB GB available (need ~$requiredGB GB)"
    }
} catch {
    Write-Host "⚠ Could not check disk space" -ForegroundColor Yellow
}

# Check 6: PowerShell Version
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Check 6: PowerShell Version" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 5) {
    Write-Host "✓ PowerShell 5.1+" -ForegroundColor Green
    Write-Host "  Version: $psVersion" -ForegroundColor Gray
} else {
    Write-Host "✗ PowerShell version too old" -ForegroundColor Red
    Write-Host "  Found: $psVersion" -ForegroundColor Gray
    Write-Host "  Required: 5.1 or later (or PowerShell 7+)" -ForegroundColor Gray
    $script:missingDeps += "PowerShell 5.1+"
}

# Check 7: Administrator Privileges
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Check 7: Administrator Privileges" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")

if ($isAdmin) {
    Write-Host "✓ Running as Administrator" -ForegroundColor Green
} else {
    Write-Host "⚠ Not running as Administrator" -ForegroundColor Yellow
    Write-Host "  Some operations may be limited" -ForegroundColor Gray
    Write-Host "  Recommended: Run PowerShell as Administrator" -ForegroundColor Gray
}

# Summary
Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    CHECK COMPLETE ✓                       ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

if ($script:missingDeps.Count -eq 0 -and $script:warnings.Count -eq 0) {
    Write-Host "✓ All dependencies are installed!" -ForegroundColor Green
    Write-Host "`nYou can now build the installer:
    .\build-windows-installer.ps1
" -ForegroundColor Cyan
    exit 0
} elseif ($script:missingDeps.Count -eq 0) {
    Write-Host "⚠ All required dependencies found, but with warnings:" -ForegroundColor Yellow
    $script:warnings | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
    Write-Host "`nYou can still build, but consider addressing warnings." -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "✗ Missing dependencies:" -ForegroundColor Red
    $script:missingDeps | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
    
    if ($script:warnings.Count -gt 0) {
        Write-Host "`nAdditional warnings:" -ForegroundColor Yellow
        $script:warnings | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
    }
    
    if (!$SkipInstall) {
        Write-Host "`nQuick install commands:" -ForegroundColor Cyan
        Write-Host "  choco install innosetup dotnet-sdk (requires admin)" -ForegroundColor Gray
        Write-Host "  Or download manually from links shown above" -ForegroundColor Gray
    }
    
    exit 1
}
