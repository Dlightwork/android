param(
    [string]$AndroidSdkRoot = "",
    [string]$JavaSdkDirectory = "",
    [string]$CmdlineToolsUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip",
    [string]$PlatformVersion = "android-34",
    [string]$BuildToolsVersion = "34.0.0",
    [switch]$SkipLicenses
)

$ErrorActionPreference = "Stop"

function Test-Jdk([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $false
    }

    $javac = Join-Path $path "bin\javac.exe"
    $jar = Join-Path $path "bin\jar.exe"
    return (Test-Path $javac) -and (Test-Path $jar)
}

function Resolve-Jdk([string]$requestedPath) {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($requestedPath)) {
        $candidates += $requestedPath
    }

    if ($env:JAVA_HOME) {
        $candidates += $env:JAVA_HOME
    }

    $javaRoot = "C:\Program Files\Java"
    if (Test-Path $javaRoot) {
        $candidates += (Join-Path $javaRoot "jdk-21")
        $candidates += (Join-Path $javaRoot "jdk-17")
        $candidates += (Join-Path $javaRoot "jdk-24")
        $candidates += (Join-Path $javaRoot "latest")

        $jdkDirs = Get-ChildItem $javaRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "jdk*" } |
            Sort-Object Name -Descending
        foreach ($dir in $jdkDirs) {
            $candidates += $dir.FullName
        }
    }

    foreach ($candidate in $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
        if (Test-Jdk $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "JDK 17+ not found. Install JDK and/or pass -JavaSdkDirectory."
}

function Write-AndroidLicenses([string]$sdkRootPath) {
    $licensesDir = Join-Path $sdkRootPath "licenses"
    New-Item -Path $licensesDir -ItemType Directory -Force | Out-Null

    @(
        "8933bad161af4178b1185d1a37fbf41ea5269c55",
        "d56f5187479451eabf01fb78af6dfcb131a6481e",
        "24333f8a63b6825ea9c5514f83c2829b004d1fee"
    ) | Set-Content -Path (Join-Path $licensesDir "android-sdk-license") -Encoding ASCII

    @(
        "84831b9409646a918e30573bab4c9c91346d8abd"
    ) | Set-Content -Path (Join-Path $licensesDir "android-sdk-preview-license") -Encoding ASCII

    @(
        "d975f751698a77b662f1254ddbeed3901e976f5a"
    ) | Set-Content -Path (Join-Path $licensesDir "intel-android-extra-license") -Encoding ASCII
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    $AndroidSdkRoot = Join-Path $repoRoot "_android_sdk"
}

$sdkRoot = $AndroidSdkRoot
if (-not (Test-Path $sdkRoot)) {
    New-Item -Path $sdkRoot -ItemType Directory -Force | Out-Null
}
$sdkRoot = (Resolve-Path $sdkRoot).Path

$jdk = Resolve-Jdk -requestedPath $JavaSdkDirectory
$env:JAVA_HOME = $jdk
$env:PATH = (Join-Path $jdk "bin") + ";" + $env:PATH

$cmdlineRoot = Join-Path $sdkRoot "cmdline-tools"
$latestRoot = Join-Path $cmdlineRoot "latest"
$sdkManager = Join-Path $latestRoot "bin\sdkmanager.bat"

if (-not (Test-Path $sdkManager)) {
    $zipPath = Join-Path $env:TEMP "norkn-android-cmdline-tools.zip"
    $extractRoot = Join-Path $env:TEMP "norkn-android-cmdline-tools"

    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }
    if (Test-Path $extractRoot) {
        Remove-Item -Path $extractRoot -Recurse -Force
    }

    Write-Host "Downloading Android command-line tools..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $CmdlineToolsUrl -OutFile $zipPath

    Write-Host "Extracting command-line tools..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

    $source = Join-Path $extractRoot "cmdline-tools"
    if (-not (Test-Path $source)) {
        throw "Unexpected archive layout: missing cmdline-tools directory."
    }

    if (Test-Path $latestRoot) {
        Remove-Item -Path $latestRoot -Recurse -Force
    }
    New-Item -Path $cmdlineRoot -ItemType Directory -Force | Out-Null
    Copy-Item -Path $source -Destination $latestRoot -Recurse -Force

    $sdkManager = Join-Path $latestRoot "bin\sdkmanager.bat"
    if (-not (Test-Path $sdkManager)) {
        throw "sdkmanager not found after extraction: $sdkManager"
    }
}

Write-Host "Android SDK root: $sdkRoot"
Write-Host "Java SDK:         $jdk"

if (-not $SkipLicenses) {
    Write-Host "Writing Android SDK license files..." -ForegroundColor Cyan
    Write-AndroidLicenses -sdkRootPath $sdkRoot
}

$packages = @(
    "platform-tools",
    "platforms;$PlatformVersion",
    "build-tools;$BuildToolsVersion"
)

Write-Host "Installing Android SDK packages..." -ForegroundColor Cyan
& $sdkManager --sdk_root=$sdkRoot @packages
if ($LASTEXITCODE -ne 0) {
    throw "sdkmanager failed with code $LASTEXITCODE"
}

$requiredPaths = @(
    (Join-Path $sdkRoot "platform-tools\adb.exe"),
    (Join-Path $sdkRoot "platforms\$PlatformVersion\android.jar"),
    (Join-Path $sdkRoot "build-tools\$BuildToolsVersion\apksigner.bat"),
    (Join-Path $sdkRoot "build-tools\$BuildToolsVersion\zipalign.exe")
)

$missing = @($requiredPaths | Where-Object { -not (Test-Path $_) })
if ($missing.Count -gt 0) {
    throw "Android SDK installation incomplete. Missing: $($missing -join ', ')"
}

Write-Host "Android SDK installation complete." -ForegroundColor Green
Write-Host "Set environment variables for this repo session:"
Write-Host "  ANDROID_SDK_ROOT=$sdkRoot"
Write-Host "  JAVA_HOME=$jdk"
