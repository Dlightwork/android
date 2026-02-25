param(
    [string]$NdkVersion = "27.2.12479018",
    [string]$AndroidSdkRoot = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$sdkCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    $sdkCandidates += $AndroidSdkRoot
}
if ($env:ANDROID_SDK_ROOT) { $sdkCandidates += $env:ANDROID_SDK_ROOT }
if ($env:ANDROID_HOME) { $sdkCandidates += $env:ANDROID_HOME }
$sdkCandidates += (Join-Path $repoRoot "_android_sdk")
$sdkCandidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk")

$sdkRoot = ""
foreach ($candidate in $sdkCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
    if (Test-Path $candidate) {
        $sdkRoot = (Resolve-Path $candidate).Path
        break
    }
}

if (-not $sdkRoot) {
    throw "Android SDK root not found. Set ANDROID_SDK_ROOT or install SDK into _android_sdk or %LOCALAPPDATA%\\Android\\Sdk"
}

$sourceRoot = Join-Path $repoRoot "_android_native/hev-socks5-tunnel"
$ndkBuild = Join-Path $sdkRoot ("ndk/{0}/ndk-build.cmd" -f $NdkVersion)
$workRoot = Join-Path $env:TEMP "norkn-android-native-build"
$destRoot = Join-Path $repoRoot "NoRKN.Android/native"

if (-not (Test-Path $sourceRoot)) {
    throw "Native source not found: $sourceRoot"
}

if (-not (Test-Path $ndkBuild)) {
    throw "NDK build tool not found: $ndkBuild`nInstall NDK first via sdkmanager (ndk;$NdkVersion)."
}

Write-Host "Preparing native build workspace..." -ForegroundColor Cyan
if (Test-Path $workRoot) {
    Remove-Item -Recurse -Force $workRoot
}
New-Item -ItemType Directory -Path $workRoot | Out-Null

# Build in temp path (without spaces) because ndk-build rejects spaced paths.
& robocopy $sourceRoot $workRoot /MIR /NFL /NDL /NJH /NJS /NC /NS | Out-Null
if ($LASTEXITCODE -gt 7) {
    throw "robocopy failed with code $LASTEXITCODE"
}

Push-Location $workRoot
try {
    Write-Host "Building tun2socks native libs..." -ForegroundColor Cyan
    & $ndkBuild NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=Android.mk NDK_APPLICATION_MK=Application.mk
    if ($LASTEXITCODE -ne 0) {
        throw "ndk-build failed with code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$abis = @("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
foreach ($abi in $abis) {
    $src = Join-Path $workRoot ("libs/{0}/libhev-socks5-tunnel.so" -f $abi)
    if (-not (Test-Path $src)) {
        throw "Missing built library: $src"
    }

    $dstDir = Join-Path $destRoot $abi
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    Copy-Item -Force $src (Join-Path $dstDir "libtun2socks.so")
}

Write-Host "Native libs copied to $destRoot" -ForegroundColor Green
