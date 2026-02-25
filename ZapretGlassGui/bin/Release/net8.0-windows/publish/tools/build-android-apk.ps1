param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$SkipNativeBuild,
    [switch]$KeepUnsignedApk
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$project = Join-Path $repoRoot "NoRKN.Android\NoRKN.Android.csproj"
$nativeBuildScript = Join-Path $repoRoot "tools\build-android-native-tun2socks.ps1"
$localDotnet = Join-Path $repoRoot ".dotnet-local\dotnet.exe"
$androidSdkDir = Join-Path $repoRoot "_android_sdk"
$xamarinDebugKeystore = Join-Path $env:LOCALAPPDATA "Xamarin\Mono for Android\debug.keystore"
$androidDebugKeystore = Join-Path $env:USERPROFILE ".android\debug.keystore"
$dotnet = if (Test-Path $localDotnet) { $localDotnet } else { "dotnet" }

if (-not (Test-Path $project)) {
    throw "Project not found: $project"
}

if (-not (Test-Path $androidSdkDir)) {
    throw "Android SDK directory not found: $androidSdkDir"
}

$buildTools = Get-ChildItem (Join-Path $androidSdkDir "build-tools") -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $buildTools) {
    throw "Android build-tools not found in $androidSdkDir\build-tools"
}

$apksigner = Join-Path $buildTools.FullName "apksigner.bat"
if (-not (Test-Path $apksigner)) {
    throw "apksigner not found: $apksigner"
}

$zipalign = Join-Path $buildTools.FullName "zipalign.exe"
if (-not (Test-Path $zipalign)) {
    throw "zipalign not found: $zipalign"
}

$debugKeystore = if (Test-Path $xamarinDebugKeystore) { $xamarinDebugKeystore } else { $androidDebugKeystore }
if (-not (Test-Path $debugKeystore)) {
    throw "Debug keystore not found. Expected: $xamarinDebugKeystore or $androidDebugKeystore"
}

Push-Location $repoRoot
try {
    if (-not $SkipNativeBuild) {
        & $nativeBuildScript
        if ($LASTEXITCODE -ne 0) {
            throw "Native build failed with code $LASTEXITCODE"
        }
    }

    & $dotnet publish $project `
        -c $Configuration `
        -f net8.0-android `
        -p:AndroidSdkDirectory=$androidSdkDir `
        -p:AndroidPackageFormat=apk
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with code $LASTEXITCODE"
    }

    $publishDir = Join-Path $repoRoot "NoRKN.Android\bin\$Configuration\net8.0-android\publish"
    $unsignedApk = Join-Path $publishDir "com.norkn.app.apk"
    $alignedApk = Join-Path $publishDir "com.norkn.app-aligned.apk"
    $signedApk = Join-Path $publishDir "com.norkn.app-Signed.apk"
    $signedApkAlias = Join-Path $publishDir "NoRKN.apk"

    if (Test-Path $unsignedApk) {
        & $zipalign -f -p -v 4 $unsignedApk $alignedApk
        if ($LASTEXITCODE -ne 0) {
            throw "zipalign failed with code $LASTEXITCODE"
        }

        & $apksigner sign `
            --ks $debugKeystore `
            --ks-key-alias androiddebugkey `
            --ks-pass pass:android `
            --key-pass pass:android `
            --v2-signing-enabled true `
            --v3-signing-enabled true `
            --out $signedApk `
            $alignedApk

        if ($LASTEXITCODE -ne 0) {
            throw "apksigner failed with code $LASTEXITCODE"
        }

        if (-not $KeepUnsignedApk) {
            Remove-Item -Force $unsignedApk -ErrorAction SilentlyContinue
            Remove-Item -Force $alignedApk -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path $signedApk)) {
        throw "Signed APK not found: $signedApk"
    }

    & $apksigner verify --verbose $signedApk
    if ($LASTEXITCODE -ne 0) {
        throw "Signed APK verification failed"
    }

    Copy-Item -Force $signedApk $signedApkAlias

    # idsig is not needed for manual install and confuses users.
    Remove-Item -Force "$signedApk.idsig" -ErrorAction SilentlyContinue
    Remove-Item -Force "$signedApkAlias.idsig" -ErrorAction SilentlyContinue

    # Keep only one APK for user install to avoid confusion with stale artifacts.
    Get-ChildItem $publishDir -File -Filter *.apk |
        Where-Object { $_.FullName -ne $signedApkAlias } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "APK build finished." -ForegroundColor Green
    Write-Host "Install this file: $signedApkAlias" -ForegroundColor Cyan
    Write-Host "Output dir:        $publishDir"
}
finally {
    Pop-Location
}
