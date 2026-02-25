#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick runner for NoRKN Windows installer
    
.DESCRIPTION
    Provides quick install/uninstall/repair operations for NoRKN
    
.PARAMETER Action
    Action to perform: Install, Uninstall, Repair, Launch
    
.PARAMETER Silent
    Use silent mode (no user prompts)
    
.PARAMETER InstallerPath
    Custom path to installer executable
    
.EXAMPLE
    .\run-installer.ps1 -Action Install
    
.EXAMPLE
    .\run-installer.ps1 -Action Uninstall -Silent
    
.EXAMPLE
    .\run-installer.ps1 -Action Launch
#>

param(
    [ValidateSet("Install", "Uninstall", "Repair", "Launch")]
    [string]$Action = "Install",
    
    [switch]$Silent,
    
    [string]$InstallerPath = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommandPath
$AppName = "NoRKN"
$AppPath = Join-Path $env:ProgramFiles $AppName

function Test-Administrator {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole] "Administrator")
}

function Find-Installer {
    param([string]$Path)
    
    if ($Path -and (Test-Path $Path)) {
        return $Path
    }
    
    $searchPath = Join-Path $ProjectRoot "dist\installer"
    $installer = Get-ChildItem -Path $searchPath -Filter "NoRKN-Setup-*.exe" -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1
    
    if ($installer) {
        return $installer.FullName
    }
    
    return $null
}

function Show-Menu {
    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              NoRKN Installer - Quick Runner               ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    Write-Host "Select action:" -ForegroundColor Yellow
    Write-Host "  1. Install NoRKN" -ForegroundColor Cyan
    Write-Host "  2. Uninstall NoRKN" -ForegroundColor Cyan
    Write-Host "  3. Repair Installation" -ForegroundColor Cyan
    Write-Host "  4. Launch NoRKN App" -ForegroundColor Cyan
    Write-Host "  5. Exit" -ForegroundColor Cyan
    Write-Host ""
    
    $choice = Read-Host "Enter choice (1-5)"
    return $choice
}

# Main execution
Write-Host "`n" -NoNewline

# Check administrator privileges
if (-not (Test-Administrator)) {
    $isAdmin = $false
    Write-Host "⚠ Running without administrator privileges" -ForegroundColor Yellow
    Write-Host "Some operations may be limited`n" -ForegroundColor Yellow
} else {
    $isAdmin = $true
}

# Find installer if needed
if ($Action -eq "Install") {
    $installerPath = Find-Installer -Path $InstallerPath
    
    if (!$installerPath) {
        Write-Error "Installer not found. Build it first using: .\build-windows-installer.ps1"
        exit 1
    }
    
    Write-Host "Found installer: $(Split-Path -Leaf $installerPath)" -ForegroundColor Green
}

# Execute action
switch ($Action) {
    "Install" {
        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-Host "Installing NoRKN" -ForegroundColor Yellow
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
        
        if (!$isAdmin) {
            Write-Host "Note: Admin privileges required for driver installation" -ForegroundColor Yellow
            Write-Host "Script will attempt to elevate...`n" -ForegroundColor Yellow
            
            # Relaunch with admin
            $params = @("-NoExit", "-Command", "cd '$ProjectRoot'; & '$($PSCommandPath)' -Action Install -Silent")
            Start-Process powershell -ArgumentList $params -Verb RunAs
            exit 0
        }
        
        $args = @()
        if ($Silent) {
            $args += "/SILENT"
            $args += "/NORESTART"
        }
        
        try {
            Write-Host "Launching installer...`n"
            $process = Start-Process -FilePath $installerPath -ArgumentList $args -PassThru -Wait
            
            if ($process.ExitCode -eq 0) {
                Write-Host "`n✓ Installation completed successfully" -ForegroundColor Green
                
                if (Test-Path $AppPath) {
                    Write-Host "  Installation path: $AppPath" -ForegroundColor Gray
                    $launchChoice = Read-Host "`nLaunch application now? (y/n)"
                    if ($launchChoice -eq "y") {
                        Start-Process "$(Join-Path $AppPath "NoRKN.exe")" -NoNewWindow
                    }
                }
            } else {
                Write-Host "⚠ Installation exited with code: $($process.ExitCode)" -ForegroundColor Yellow
            }
        } catch {
            Write-Error "Installation failed: $_"
            exit 1
        }
    }
    
    "Uninstall" {
        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-Host "Uninstalling NoRKN" -ForegroundColor Yellow
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
        
        if (!$isAdmin) {
            Write-Host "Note: Admin privileges required for uninstall" -ForegroundColor Yellow
            Write-Host "Script will attempt to elevate...`n" -ForegroundColor Yellow
            
            $params = @("-NoExit", "-Command", "cd '$ProjectRoot'; & '$($PSCommandPath)' -Action Uninstall -Silent")
            Start-Process powershell -ArgumentList $params -Verb RunAs
            exit 0
        }
        
        # Look for uninstaller
        $uninstallerExe = Join-Path $AppPath "unins000.exe"
        
        if (!(Test-Path $uninstallerExe)) {
            Write-Host "✗ NoRKN uninstaller not found. Application may not be installed." -ForegroundColor Red
            Write-Host "  Expected: $uninstallerExe" -ForegroundColor Gray
            exit 1
        }
        
        Write-Host "Found uninstaller: $uninstallerExe`n"
        
        if (!$Silent) {
            $confirm = Read-Host "Confirm uninstall? (y/n)"
            if ($confirm -ne "y") {
                Write-Host "Cancelled" -ForegroundColor Yellow
                exit 0
            }
        }
        
        try {
            Write-Host "Launching uninstaller...`n"
            $args = @()
            if ($Silent) {
                $args = @("/SILENT")
            }
            
            $process = Start-Process -FilePath $uninstallerExe -ArgumentList $args -PassThru -Wait
            
            if ($process.ExitCode -eq 0) {
                Write-Host "`n✓ Uninstallation completed successfully" -ForegroundColor Green
            } else {
                Write-Host "⚠ Uninstallation exited with code: $($process.ExitCode)" -ForegroundColor Yellow
            }
        } catch {
            Write-Error "Uninstallation failed: $_"
            exit 1
        }
    }
    
    "Repair" {
        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-Host "Repairing NoRKN Installation" -ForegroundColor Yellow
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
        
        if (!$isAdmin) {
            Write-Host "Note: Admin privileges required for repair" -ForegroundColor Yellow
            Write-Host "Script will attempt to elevate...`n" -ForegroundColor Yellow
            
            $params = @("-NoExit", "-Command", "cd '$ProjectRoot'; & '$($PSCommandPath)' -Action Repair -Silent")
            Start-Process powershell -ArgumentList $params -Verb RunAs
            exit 0
        }
        
        Write-Host "Repair checks:" -ForegroundColor Cyan
        
        # Check installation directory
        if (Test-Path $AppPath) {
            Write-Host "✓ Installation directory exists: $AppPath" -ForegroundColor Green
        } else {
            Write-Host "✗ Installation directory not found: $AppPath" -ForegroundColor Red
            exit 1
        }
        
        # Check main executable
        $exePath = Join-Path $AppPath "NoRKN.exe"
        if (Test-Path $exePath) {
            Write-Host "✓ Main executable found" -ForegroundColor Green
        } else {
            Write-Host "✗ Main executable not found: $exePath" -ForegroundColor Red
        }
        
        # Check registry
        $regPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NoRKN"
        if (Test-Path $regPath) {
            Write-Host "✓ Registry entry found" -ForegroundColor Green
        } else {
            Write-Host "⚠ Registry entry missing (may be corrupted)" -ForegroundColor Yellow
        }
        
        # Run installer in repair mode
        $installerPath = Find-Installer -Path $InstallerPath
        if ($installerPath) {
            Write-Host "`nLaunching repair...`n"
            $process = Start-Process -FilePath $installerPath -ArgumentList "/REPAIR" -PassThru -Wait
            
            if ($process.ExitCode -eq 0) {
                Write-Host "`n✓ Repair completed" -ForegroundColor Green
            } else {
                Write-Host "⚠ Repair exited with code: $($process.ExitCode)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "⚠ Installer not found, cannot run repair" -ForegroundColor Yellow
        }
    }
    
    "Launch" {
        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-Host "Launching NoRKN" -ForegroundColor Yellow
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan
        
        $exePath = Join-Path $AppPath "NoRKN.exe"
        
        if (!(Test-Path $exePath)) {
            Write-Host "✗ Application not found: $exePath" -ForegroundColor Red
            Write-Host "Please install NoRKN first" -ForegroundColor Yellow
            exit 1
        }
        
        Write-Host "Launching: $exePath`n"
        try {
            Start-Process -FilePath $exePath -NoNewWindow
            Write-Host "✓ Application launched" -ForegroundColor Green
        } catch {
            Write-Error "Failed to launch application: $_"
            exit 1
        }
    }
}

Write-Host "`n"
