#!/usr/bin/env pwsh
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$AndroidSdkDirectory = "",
    [string]$JavaSdkDirectory = "",
    [switch]$SkipAssetSync,
    [switch]$SkipNativeBuild,
    [switch]$ForceNativeBuild,
    [switch]$SkipWorkloadInstall,
    [switch]$SkipSdkInstall,
    [string]$SignKey = "",
    [string]$KeyAlias = "",
    [string]$KeyPassword = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommandPath }
$toolScript = Join-Path $repoRoot "tools\build-android-apk.ps1"

if (-not (Test-Path $toolScript)) {
    throw "Build tool script not found: $toolScript"
}

if ($SignKey -or $KeyAlias -or $KeyPassword) {
    Write-Warning "Custom signing arguments are currently ignored by this wrapper."
    Write-Warning "APK is produced by dotnet publish and copied to build/android/NoRKN.apk."
}

& $toolScript `
    -Configuration $Configuration `
    -AndroidSdkDirectory $AndroidSdkDirectory `
    -JavaSdkDirectory $JavaSdkDirectory `
    -SkipAssetSync:$SkipAssetSync `
    -SkipNativeBuild:$SkipNativeBuild `
    -ForceNativeBuild:$ForceNativeBuild `
    -SkipWorkloadInstall:$SkipWorkloadInstall `
    -SkipSdkInstall:$SkipSdkInstall

if ($LASTEXITCODE -ne 0) {
    throw "Android APK build failed with code $LASTEXITCODE"
}
