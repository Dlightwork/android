param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [string]$DotnetPath = "",
    [string]$AndroidSdkDirectory = "",
    [string]$JavaSdkDirectory = "",
    [switch]$SkipAssetSync,
    [switch]$SkipNativeBuild,
    [switch]$ForceNativeBuild,
    [switch]$SkipWorkloadInstall,
    [switch]$SkipSdkInstall
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$message) {
    Write-Host ""
    Write-Host "== $message ==" -ForegroundColor Cyan
}

function Invoke-Checked([scriptblock]$action, [string]$failureMessage) {
    & $action
    if ($LASTEXITCODE -ne 0) {
        throw "$failureMessage (exit code $LASTEXITCODE)"
    }
}

function Resolve-Dotnet([string]$repoRoot, [string]$requestedPath) {
    if (-not [string]::IsNullOrWhiteSpace($requestedPath)) {
        if (-not (Test-Path $requestedPath)) {
            throw "Dotnet path does not exist: $requestedPath"
        }
        return (Resolve-Path $requestedPath).Path
    }

    $localDotnet = Join-Path $repoRoot ".dotnet-local\dotnet.exe"
    if (Test-Path $localDotnet) {
        return $localDotnet
    }

    return "dotnet"
}

function Resolve-AndroidSdk([string]$repoRoot, [string]$requestedPath) {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($requestedPath)) {
        $candidates += $requestedPath
    }

    if ($env:ANDROID_SDK_ROOT) { $candidates += $env:ANDROID_SDK_ROOT }
    if ($env:ANDROID_HOME) { $candidates += $env:ANDROID_HOME }
    $candidates += (Join-Path $repoRoot "_android_sdk")
    $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk")

    foreach ($candidate in $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    return ""
}

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

    return ""
}

function Test-AndroidWorkloadInstalled([string]$dotnet) {
    $output = & $dotnet workload list 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return ($output | Select-String -Pattern "(^|\s)android(\s|$)" -SimpleMatch:$false) -ne $null
}

function Ensure-AndroidWorkload([string]$dotnet) {
    if (Test-AndroidWorkloadInstalled -dotnet $dotnet) {
        Write-Host "Android workload already installed." -ForegroundColor Green
        return
    }

    Write-Host "Installing android workload..." -ForegroundColor Yellow
    Invoke-Checked -failureMessage "dotnet workload install android failed" -action {
        & $dotnet workload install android `
            --source https://api.nuget.org/v3/index.json `
            --ignore-failed-sources `
            --verbosity minimal
    }
}

function Get-NativeLibState([string]$repoRoot) {
    $abis = @("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
    $missing = @()
    foreach ($abi in $abis) {
        $path = Join-Path $repoRoot "NoRKN.Android\native\$abi\libtun2socks.so"
        if (-not (Test-Path $path)) {
            $missing += $path
        }
    }

    return [PSCustomObject]@{
        Missing = $missing
        HasAll = ($missing.Count -eq 0)
    }
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$project = Join-Path $repoRoot "NoRKN.Android\NoRKN.Android.csproj"
$assetSyncScript = Join-Path $repoRoot "tools\sync-android-zapret-assets.ps1"
$nativeBuildScript = Join-Path $repoRoot "tools\build-android-native-tun2socks.ps1"
$sdkInstallScript = Join-Path $repoRoot "tools\install-android-sdk.ps1"
$dotnet = Resolve-Dotnet -repoRoot $repoRoot -requestedPath $DotnetPath
$resolvedJdk = Resolve-Jdk -requestedPath $JavaSdkDirectory
$resolvedSdk = Resolve-AndroidSdk -repoRoot $repoRoot -requestedPath $AndroidSdkDirectory

if (-not (Test-Path $project)) {
    throw "Project not found: $project"
}

Push-Location $repoRoot
try {
    Write-Step "Environment"
    Write-Host "Repository: $repoRoot"
    Write-Host "Project:    $project"
    Write-Host "Dotnet:     $dotnet"
    if ($resolvedJdk) {
        Write-Host "JavaSdk:    $resolvedJdk"
    } else {
        Write-Host "JavaSdk:    not found"
    }
    if ($resolvedSdk) {
        Write-Host "AndroidSdk: $resolvedSdk"
    } else {
        Write-Host "AndroidSdk: not found"
    }

    Invoke-Checked -failureMessage "dotnet --version failed" -action {
        & $dotnet --version
    }

    if (-not $SkipWorkloadInstall) {
        Write-Step "Android Workload"
        Ensure-AndroidWorkload -dotnet $dotnet
        Invoke-Checked -failureMessage "dotnet workload restore failed" -action {
            & $dotnet workload restore $project --verbosity minimal
        }
    }

    if (-not $resolvedJdk) {
        throw "JDK 17+ not found. Install JDK or pass -JavaSdkDirectory."
    }

    $env:JAVA_HOME = $resolvedJdk
    $env:PATH = (Join-Path $resolvedJdk "bin") + ";" + $env:PATH

    if (-not $resolvedSdk -and -not $SkipSdkInstall) {
        Write-Step "Android SDK"
        if (-not (Test-Path $sdkInstallScript)) {
            throw "Android SDK install script not found: $sdkInstallScript"
        }

        $targetSdkRoot = if ([string]::IsNullOrWhiteSpace($AndroidSdkDirectory)) {
            Join-Path $repoRoot "_android_sdk"
        } else {
            $AndroidSdkDirectory
        }

        & $sdkInstallScript -AndroidSdkRoot $targetSdkRoot -JavaSdkDirectory $resolvedJdk
        if ($LASTEXITCODE -ne 0) {
            throw "Android SDK installation failed with code $LASTEXITCODE"
        }

        $resolvedSdk = Resolve-AndroidSdk -repoRoot $repoRoot -requestedPath $targetSdkRoot
    }

    if (-not $resolvedSdk) {
        throw "Android SDK not found. Run tools/install-android-sdk.ps1 or pass -AndroidSdkDirectory."
    }

    if (-not $SkipAssetSync) {
        Write-Step "Sync zapret assets"
        if (-not (Test-Path $assetSyncScript)) {
            throw "Asset sync script not found: $assetSyncScript"
        }

        & $assetSyncScript
        if ($LASTEXITCODE -ne 0) {
            throw "Asset sync failed with code $LASTEXITCODE"
        }
    }

    if (-not $SkipNativeBuild) {
        $nativeState = Get-NativeLibState -repoRoot $repoRoot
        $needNativeBuild = $ForceNativeBuild -or (-not $nativeState.HasAll)

        if ($needNativeBuild) {
            Write-Step "Build native tun2socks"
            if (-not (Test-Path $nativeBuildScript)) {
                throw "Native build script not found: $nativeBuildScript"
            }

            & $nativeBuildScript
            if ($LASTEXITCODE -ne 0) {
                throw "Native build failed with code $LASTEXITCODE"
            }
        } else {
            Write-Host "Native libraries already present. Skipping native build." -ForegroundColor Green
        }
    }

    Write-Step "dotnet publish"
    $publishArgs = @(
        "publish",
        $project,
        "-c", $Configuration,
        "-f", "net8.0-android",
        "-p:AndroidPackageFormat=apk",
        "-v", "minimal"
    )

    if ($resolvedSdk) {
        $publishArgs += "-p:AndroidSdkDirectory=$resolvedSdk"
    }
    if ($resolvedJdk) {
        $publishArgs += "-p:JavaSdkDirectory=$resolvedJdk"
    }

    Invoke-Checked -failureMessage "dotnet publish failed" -action {
        & $dotnet @publishArgs
    }

    $publishDir = Join-Path $repoRoot "NoRKN.Android\bin\$Configuration\net8.0-android\publish"
    if (-not (Test-Path $publishDir)) {
        throw "Publish directory not found: $publishDir"
    }

    $apkCandidates = Get-ChildItem -Path $publishDir -File -Filter *.apk | Sort-Object LastWriteTime -Descending
    if (-not $apkCandidates) {
        throw "No APK produced in $publishDir"
    }

    # Prefer fresh signed output from current publish run.
    $preferred = $apkCandidates | Where-Object { $_.Name -ieq "com.norkn.app-Signed.apk" } | Select-Object -First 1
    if (-not $preferred) {
        $preferred = $apkCandidates | Where-Object { $_.Name -match "Signed\.apk$" } | Select-Object -First 1
    }
    if (-not $preferred) {
        $preferred = $apkCandidates | Where-Object { $_.Name -ieq "com.norkn.app.apk" } | Select-Object -First 1
    }
    if (-not $preferred) {
        $preferred = $apkCandidates | Select-Object -First 1
    }

    $artifactsDir = Join-Path $repoRoot "build\android"
    New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null

    $artifactName = "NoRKN-$Configuration.apk"
    $artifactPath = Join-Path $artifactsDir $artifactName
    Copy-Item -Path $preferred.FullName -Destination $artifactPath -Force

    # Keep stable install alias.
    $aliasPath = Join-Path $artifactsDir "NoRKN.apk"
    Copy-Item -Path $preferred.FullName -Destination $aliasPath -Force

    $apksigner = ""
    if ($resolvedSdk) {
        $buildToolsRoot = Join-Path $resolvedSdk "build-tools"
        if (Test-Path $buildToolsRoot) {
            $buildTools = Get-ChildItem $buildToolsRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
            if ($buildTools) {
                $candidate = Join-Path $buildTools.FullName "apksigner.bat"
                if (Test-Path $candidate) {
                    $apksigner = $candidate
                }
            }
        }
    }

    if ($apksigner) {
        Write-Step "APK verify"
        & $apksigner verify --verbose $artifactPath
        if ($LASTEXITCODE -ne 0) {
            throw "apksigner verification failed"
        }
    }

    Write-Step "Done"
    Write-Host "Final APK: $artifactPath" -ForegroundColor Green
    Write-Host "Alias APK: $aliasPath"
    Write-Host "Install:   .\\tools\\install-android-apk.ps1 -ApkPath `"$aliasPath`""
}
finally {
    Pop-Location
}
