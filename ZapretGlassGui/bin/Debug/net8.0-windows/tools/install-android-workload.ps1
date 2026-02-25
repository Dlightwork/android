param(
    [string]$SdkVersion = "8.0.418",
    [string]$DotnetInstallUrl = "https://dot.net/v1/dotnet-install.ps1"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$project = Join-Path $repoRoot "NoRKN.Android\NoRKN.Android.csproj"
$localDotnetDir = Join-Path $repoRoot ".dotnet-local"
$localDotnet = Join-Path $localDotnetDir "dotnet.exe"
$installerScript = Join-Path $PSScriptRoot "dotnet-install.ps1"

if (-not (Test-Path $project)) {
    throw "Project not found: $project"
}

Push-Location $repoRoot
try {
    if (-not (Test-Path $localDotnet)) {
        Write-Host "Installing local .NET SDK $SdkVersion to $localDotnetDir..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $DotnetInstallUrl -OutFile $installerScript
        powershell -ExecutionPolicy Bypass -File $installerScript -Version $SdkVersion -InstallDir $localDotnetDir -NoPath
    }

    Write-Host "Using local dotnet: $localDotnet" -ForegroundColor Cyan
    & $localDotnet --version

    Write-Host "Installing Android workload (nuget.org only)..." -ForegroundColor Cyan
    & $localDotnet workload install android `
        --skip-manifest-update `
        --disable-parallel `
        --source https://api.nuget.org/v3/index.json `
        --ignore-failed-sources `
        --verbosity minimal

    Write-Host "Android workload installed." -ForegroundColor Green
}
finally {
    Pop-Location
}
