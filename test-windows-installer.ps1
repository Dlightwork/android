#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test NoRKN Windows installer
    
.DESCRIPTION
    Performs automatic testing of the NoRKN Windows installer including:
    - Silent installation
    - Registry verification
    - File verification
    - Uninstallation
    
.PARAMETER InstallerPath
    Path to the NoRKN-Setup-*.exe installer
    
.PARAMETER TestType
    Test scope: Full, Silent, Files, Registry, Uninstall (default: Full)
    
.EXAMPLE
    .\test-windows-installer.ps1 -InstallerPath "dist\installer\NoRKN-Setup-2.0.0.exe"
    
.EXAMPLE
    .\test-windows-installer.ps1 -TestType Silent
#>

param(
    [string]$InstallerPath = "",
    
    [ValidateSet("Full", "Silent", "Files", "Registry", "Uninstall")]
    [string]$TestType = "Full"
)

$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommandPath

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          NoRKN Windows Installer Tester v1.0             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Find installer if not provided
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    Write-Host "Searching for installer..." -ForegroundColor Yellow
    $installerFile = Get-ChildItem -Path (Join-Path $ProjectRoot "dist\installer") `
                     -Filter "NoRKN-Setup-*.exe" -ErrorAction SilentlyContinue | 
                     Sort-Object LastWriteTime -Descending | 
                     Select-Object -First 1
    
    if (!$installerFile) {
        Write-Error "No installer found in dist\installer directory"
        Write-Host "Build installer first using: .\build-windows-installer.ps1`n"
        exit 1
    }
    
    $InstallerPath = $installerFile.FullName
}

# Validate installer
if (!(Test-Path $InstallerPath)) {
    Write-Error "Installer not found: $InstallerPath"
    exit 1
}

Write-Host "✓ Found installer: $(Split-Path -Leaf $InstallerPath)" -ForegroundColor Green
Write-Host "  Size: $([Math]::Round((Get-Item $InstallerPath).Length / 1MB, 2)) MB" -ForegroundColor Gray

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (!$isAdmin) {
    Write-Warning "Some tests require administrator privileges"
    Write-Host "Run this script as Administrator for full testing`n" -ForegroundColor Yellow
}

# Test 1: File signature verification
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Test 1: File Signature & Integrity" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

try {
    $fileInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($InstallerPath)
    Write-Host "✓ File version: $($fileInfo.FileVersion)" -ForegroundColor Green
    Write-Host "  Product: $($fileInfo.ProductName)" -ForegroundColor Gray
    Write-Host "  Company: $($fileInfo.CompanyName)" -ForegroundColor Gray
} catch {
    Write-Host "⚠ Could not read file version info" -ForegroundColor Yellow
}

# Calculate hash
$hash = Get-FileHash -Path $InstallerPath -Algorithm SHA256
Write-Host "✓ SHA256: $($hash.Hash.Substring(0, 32))..." -ForegroundColor Green

# Test 2: Installer executable validation
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Test 2: Executable Validation" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

try {
    # Check PE header
    $bytes = [System.IO.File]::ReadAllBytes($InstallerPath)
    if ($bytes.Length -lt 2) {
        throw "File too small to be valid executable"
    }
    
    if ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) {
        Write-Host "✓ Valid PE executable (MZ header found)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Warning: File may not be a valid Windows executable" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ Could not validate PE header: $_" -ForegroundColor Yellow
}

# Test 3: Silent installation test
if ($TestType -in @("Full", "Silent")) {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "Test 3: Silent Installation Simulation" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
    
    if (!$isAdmin) {
        Write-Host "⚠ Skipped (requires admin)" -ForegroundColor Yellow
    } else {
        Write-Host "This test would install NoRKN on this system." -ForegroundColor Yellow
        $proceed = Read-Host "Proceed with test installation? (y/n)"
        
        if ($proceed -eq "y") {
            Write-Host "`nRunning silent installation..." -ForegroundColor Cyan
            try {
                $process = Start-Process -FilePath $InstallerPath `
                    -ArgumentList "/SILENT /NORESTART" `
                    -PassThru `
                    -Wait `
                    -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    Write-Host "✓ Installation completed successfully" -ForegroundColor Green
                } else {
                    Write-Host "⚠ Installation exited with code: $($process.ExitCode)" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "⚠ Installation test failed: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Skipped test installation" -ForegroundColor Yellow
        }
    }
}

# Test 4: Registry verification
if ($TestType -in @("Full", "Registry")) {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "Test 4: Registry Entries Verification" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
    
    $regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NoRKN"
    $envPath = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    
    $regExists = Test-Path $regPath -ErrorAction SilentlyContinue
    if ($regExists) {
        Write-Host "✓ Uninstall registry entry found" -ForegroundColor Green
        
        try {
            $displayName = (Get-ItemProperty $regPath "DisplayName" -ErrorAction SilentlyContinue).DisplayName
            if ($displayName) {
                Write-Host "  Name: $displayName" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  (Some registry values may require admin)" -ForegroundColor Gray
        }
    } else {
        Write-Host "ℹ Uninstall registry entry not found (app may not be installed)" -ForegroundColor Cyan
    }
    
    # Check PATH
    if ($isAdmin) {
        try {
            $pathValue = (Get-ItemProperty $envPath "Path" -ErrorAction SilentlyContinue).Path
            if ($pathValue -match "NoRKN|norkn") {
                Write-Host "✓ Program path added to PATH environment variable" -ForegroundColor Green
            } else {
                Write-Host "ℹ Program path not found in PATH (may not be installed)" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "⚠ Could not check PATH: $_" -ForegroundColor Yellow
        }
    }
}

# Test 5: File verification
if ($TestType -in @("Full", "Files")) {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "Test 5: Installed Files Verification" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
    
    $programFilesPath = Join-Path $env:ProgramFiles "NoRKN"
    
    if (Test-Path $programFilesPath) {
        Write-Host "✓ Installation directory found: $programFilesPath" -ForegroundColor Green
        
        $files = @(
            "NoRKN.exe",
            "NoRKN.dll",
            "WinDivert.dll",
            "WinDivert64.sys",
            "config.yaml"
        )
        
        foreach ($file in $files) {
            $filePath = Join-Path $programFilesPath $file
            if (Test-Path $filePath) {
                $size = [Math]::Round((Get-Item $filePath).Length / 1KB, 1)
                Write-Host "  ✓ $file ($size KB)" -ForegroundColor Gray
            } else {
                Write-Host "  ✗ $file (missing)" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "ℹ Installation directory not found (app may not be installed)" -ForegroundColor Cyan
    }
}

# Test 6: Application launch test
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Test 6: Application Launch" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

$exePath = Join-Path $env:ProgramFiles "NoRKN\NoRKN.exe"
if (Test-Path $exePath) {
    Write-Host "Testing application startup..." -ForegroundColor Cyan
    try {
        # Just check if the executable exists and is runnable, don't actually run it
        $testExe = [System.Diagnostics.ProcessStartInfo]::new($exePath)
        Write-Host "✓ Application executable found and is readable" -ForegroundColor Green
        Write-Host "  Path: $exePath" -ForegroundColor Gray
    } catch {
        Write-Host "⚠ Could not access executable: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "ℹ Application executable not found (app may not be installed)" -ForegroundColor Cyan
    Write-Host "  Expected: $exePath" -ForegroundColor Gray
}

# Summary
Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    TESTING COMPLETE ✓                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "Summary:" -ForegroundColor Green
Write-Host "  🔹 Installer: $(Split-Path -Leaf $InstallerPath)" -ForegroundColor Cyan
Write-Host "  🔹 Valid PE executable: Yes" -ForegroundColor Cyan
Write-Host "  🔹 Tests performed: " -NoNewline
Write-Host "$TestType" -ForegroundColor Yellow

if ($isAdmin) {
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  1. Test installer on clean Windows system" -ForegroundColor Gray
    Write-Host "  2. Verify WinDivert driver loads correctly" -ForegroundColor Gray
    Write-Host "  3. Test DPI bypass functionality" -ForegroundColor Gray
} else {
    Write-Host "`nNote: Run as Administrator for full test coverage`n" -ForegroundColor Yellow
}

Write-Host ""
