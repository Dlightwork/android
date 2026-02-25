param(
    [string]$SdkVersion = "",
    [string]$DotnetInstallUrl = "https://dot.net/v1/dotnet-install.ps1"
)

$ErrorActionPreference = "Stop"

function Get-DotnetMajor([string]$dotnetPath) {
    $raw = & $dotnetPath --version
    if ($LASTEXITCODE -ne 0) {
        return -1
    }

    $parts = $raw.Trim().Split('.')
    if ($parts.Length -lt 1) {
        return -1
    }

    $major = -1
    [void][int]::TryParse($parts[0], [ref]$major)
    return $major
}

function Test-AndroidWorkloadInstalled([string]$dotnetPath) {
    $out = & $dotnetPath workload list 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return ($out | Select-String -Pattern "(^|\s)android(\s|$)" -SimpleMatch:$false) -ne $null
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$localDotnetDir = Join-Path $repoRoot ".dotnet-local"
$localDotnet = Join-Path $localDotnetDir "dotnet.exe"
$installerScript = Join-Path $PSScriptRoot "dotnet-install.ps1"

$dotnet = "dotnet"
$major = Get-DotnetMajor -dotnetPath $dotnet

if ($major -lt 8) {
    if (-not (Test-Path $localDotnet)) {
        if (-not (Test-Path $installerScript)) {
            Invoke-WebRequest -Uri $DotnetInstallUrl -OutFile $installerScript
        }

        $installArgs = @("-InstallDir", $localDotnetDir, "-NoPath")
        if ([string]::IsNullOrWhiteSpace($SdkVersion)) {
            $installArgs += @("-Channel", "8.0")
        } else {
            $installArgs += @("-Version", $SdkVersion)
        }

        Write-Host "Installing local .NET SDK into $localDotnetDir..." -ForegroundColor Cyan
        & powershell -ExecutionPolicy Bypass -File $installerScript @installArgs
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet-install failed with code $LASTEXITCODE"
        }
    }

    $dotnet = $localDotnet
}

Write-Host "Using dotnet: $dotnet" -ForegroundColor Cyan
& $dotnet --version

if (Test-AndroidWorkloadInstalled -dotnetPath $dotnet) {
    Write-Host "Android workload already installed." -ForegroundColor Green
    exit 0
}

Write-Host "Installing android workload..." -ForegroundColor Cyan
& $dotnet workload install android `
    --source https://api.nuget.org/v3/index.json `
    --ignore-failed-sources `
    --verbosity minimal

if ($LASTEXITCODE -ne 0) {
    throw "dotnet workload install android failed with code $LASTEXITCODE"
}

Write-Host "Android workload installed." -ForegroundColor Green
