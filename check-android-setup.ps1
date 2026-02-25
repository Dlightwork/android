#!/usr/bin/env pwsh
$ErrorActionPreference = "Continue"

$repoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommandPath }
$projectDir = Join-Path $repoRoot "NoRKN.Android"
$projectFile = Join-Path $projectDir "NoRKN.Android.csproj"

function Test-Jdk([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $false
    }

    return (Test-Path (Join-Path $path "bin\javac.exe")) -and
           (Test-Path (Join-Path $path "bin\jar.exe"))
}

function Resolve-Jdk() {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
    $javaRoot = "C:\Program Files\Java"
    if (Test-Path $javaRoot) {
        $candidates += (Join-Path $javaRoot "jdk-21")
        $candidates += (Join-Path $javaRoot "jdk-17")
        $candidates += (Join-Path $javaRoot "jdk-24")
        $candidates += (Join-Path $javaRoot "latest")
    }

    foreach ($candidate in $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
        if (Test-Jdk $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return ""
}

function Resolve-AndroidSdk([string]$repoRootPath) {
    $candidates = @()
    if ($env:ANDROID_SDK_ROOT) { $candidates += $env:ANDROID_SDK_ROOT }
    if ($env:ANDROID_HOME) { $candidates += $env:ANDROID_HOME }
    $candidates += (Join-Path $repoRootPath "_android_sdk")
    $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk")

    foreach ($candidate in $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return ""
}

$checks = @(
    @{ Name = "Android project"; Path = $projectFile; Critical = $true },
    @{ Name = "MainActivity"; Path = (Join-Path $projectDir "MainActivity.cs"); Critical = $true },
    @{ Name = "VpnService"; Path = (Join-Path $projectDir "NorknVpnService.cs"); Critical = $true },
    @{ Name = "Assets sync script"; Path = (Join-Path $repoRoot "tools\sync-android-zapret-assets.ps1"); Critical = $true },
    @{ Name = "Build script"; Path = (Join-Path $repoRoot "tools\build-android-apk.ps1"); Critical = $true },
    @{ Name = "Native arm64"; Path = (Join-Path $projectDir "native\arm64-v8a\libtun2socks.so"); Critical = $true },
    @{ Name = "Native armv7"; Path = (Join-Path $projectDir "native\armeabi-v7a\libtun2socks.so"); Critical = $true },
    @{ Name = "Native x86"; Path = (Join-Path $projectDir "native\x86\libtun2socks.so"); Critical = $true },
    @{ Name = "Native x64"; Path = (Join-Path $projectDir "native\x86_64\libtun2socks.so"); Critical = $true },
    @{ Name = "Zapret lists"; Path = (Join-Path $projectDir "zapret\lists"); Critical = $true },
    @{ Name = "Zapret lua"; Path = (Join-Path $projectDir "zapret\lua"); Critical = $true },
    @{ Name = "Zapret presets"; Path = (Join-Path $projectDir "zapret\presets"); Critical = $false }
)

$criticalFailed = 0
$totalFailed = 0

Write-Host ""
Write-Host "NoRKN Android environment check" -ForegroundColor Cyan
Write-Host "Repository: $repoRoot"
Write-Host ""

foreach ($check in $checks) {
    if (Test-Path $check.Path) {
        Write-Host "[OK]  $($check.Name)"
    } else {
        Write-Host "[ERR] $($check.Name): $($check.Path)" -ForegroundColor Red
        $totalFailed++
        if ($check.Critical) {
            $criticalFailed++
        }
    }
}

Write-Host ""
Write-Host "Toolchain:" -ForegroundColor Cyan

try {
    $dotnetVersion = dotnet --version
    Write-Host "[OK]  dotnet: $dotnetVersion"
} catch {
    Write-Host "[ERR] dotnet not available" -ForegroundColor Red
    $criticalFailed++
    $totalFailed++
}

try {
    $workloads = dotnet workload list 2>&1
    if ($workloads | Select-String -Pattern "(^|\s)android(\s|$)" -SimpleMatch:$false) {
        Write-Host "[OK]  dotnet android workload installed"
    } else {
        Write-Host "[ERR] dotnet android workload not installed" -ForegroundColor Red
        $criticalFailed++
        $totalFailed++
    }
} catch {
    Write-Host "[ERR] cannot query dotnet workloads" -ForegroundColor Red
    $criticalFailed++
    $totalFailed++
}

$jdkPath = Resolve-Jdk
if ($jdkPath) {
    Write-Host "[OK]  JDK: $jdkPath"
} else {
    Write-Host "[ERR] JDK 17+ not found" -ForegroundColor Red
    $criticalFailed++
    $totalFailed++
}

$sdkPath = Resolve-AndroidSdk -repoRootPath $repoRoot
if ($sdkPath) {
    Write-Host "[OK]  Android SDK: $sdkPath"
} else {
    Write-Host "[ERR] Android SDK not found" -ForegroundColor Red
    $criticalFailed++
    $totalFailed++
}

try {
    $adbLine = (adb version 2>&1 | Select-Object -First 1)
    if ($adbLine) {
        Write-Host "[OK]  adb: $adbLine"
    } else {
        Write-Host "[WARN] adb not found (installation to device will fail)"
    }
} catch {
    Write-Host "[WARN] adb not found (installation to device will fail)"
}

Write-Host ""
if ($criticalFailed -eq 0) {
    Write-Host "Critical checks passed." -ForegroundColor Green
    Write-Host "Build: .\\build-android-apk.ps1 -Configuration Release"
    exit 0
}

Write-Host "Critical checks failed: $criticalFailed (total failed: $totalFailed)" -ForegroundColor Red
exit 1
