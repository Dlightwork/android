#!/usr/bin/env pwsh
param(
    [string]$Configuration = "Release",
    [string]$PackageId = "com.norkn.app",
    [string]$ApkPath = "",
    [string]$Serial = "",
    [int]$RetryCount = 5
)

$ErrorActionPreference = "Stop"

$repoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommandPath }
$toolScript = Join-Path $repoRoot "tools\install-android-apk.ps1"

if (-not (Test-Path $toolScript)) {
    throw "Install tool script not found: $toolScript"
}

& $toolScript `
    -Configuration $Configuration `
    -PackageId $PackageId `
    -ApkPath $ApkPath `
    -Serial $Serial `
    -RetryCount $RetryCount

if ($LASTEXITCODE -ne 0) {
    throw "Android APK install failed with code $LASTEXITCODE"
}
