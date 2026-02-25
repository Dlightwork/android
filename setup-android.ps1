#!/usr/bin/env pwsh
param(
    [switch]$SkipWorkloadInstall,
    [switch]$SkipSdkInstall
)

$ErrorActionPreference = "Stop"

$repoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommandPath }
$workloadScript = Join-Path $repoRoot "tools\install-android-workload.ps1"
$sdkScript = Join-Path $repoRoot "tools\install-android-sdk.ps1"
$syncScript = Join-Path $repoRoot "tools\sync-android-zapret-assets.ps1"
$checkScript = Join-Path $repoRoot "check-android-setup.ps1"

Write-Host ""
Write-Host "NoRKN Android setup" -ForegroundColor Cyan
Write-Host "Repository: $repoRoot"

if (-not $SkipWorkloadInstall) {
    if (-not (Test-Path $workloadScript)) {
        throw "Missing script: $workloadScript"
    }

    Write-Host ""
    Write-Host "Installing/checking android workload..." -ForegroundColor Cyan
    & $workloadScript
    if ($LASTEXITCODE -ne 0) {
        throw "Android workload setup failed with code $LASTEXITCODE"
    }
}

if (-not $SkipSdkInstall) {
    if (-not (Test-Path $sdkScript)) {
        throw "Missing script: $sdkScript"
    }

    Write-Host ""
    Write-Host "Installing/checking Android SDK..." -ForegroundColor Cyan
    & $sdkScript
    if ($LASTEXITCODE -ne 0) {
        throw "Android SDK setup failed with code $LASTEXITCODE"
    }
}

if (-not (Test-Path $syncScript)) {
    throw "Missing script: $syncScript"
}

Write-Host ""
Write-Host "Syncing zapret assets to NoRKN.Android..." -ForegroundColor Cyan
& $syncScript
if ($LASTEXITCODE -ne 0) {
    throw "Asset sync failed with code $LASTEXITCODE"
}

if (Test-Path $checkScript) {
    Write-Host ""
    Write-Host "Running project checks..." -ForegroundColor Cyan
    & $checkScript
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Some checks failed. Review output above."
    }
}

Write-Host ""
Write-Host "Setup completed." -ForegroundColor Green
Write-Host "Build command: .\\build-android-apk.ps1 -Configuration Release"
