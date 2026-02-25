param()

$ErrorActionPreference = "Continue"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host "Stopping dotnet/msiexec processes..."
Get-Process dotnet -ErrorAction SilentlyContinue | ForEach-Object {
    try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch { Write-Host "Cannot stop dotnet PID $($_.Id): $($_.Exception.Message)" -ForegroundColor Yellow }
}
Get-Process msiexec -ErrorAction SilentlyContinue | ForEach-Object {
    try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch { Write-Host "Cannot stop msiexec PID $($_.Id): $($_.Exception.Message)" -ForegroundColor Yellow }
}

$temp = $env:TEMP
Write-Host "Cleaning workload temp artifacts in $temp ..."
Get-ChildItem $temp -Force -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "Microsoft.NET.Workload_*" -or
        $_.Name -like "dotnet-sdk-advertising-temp*" -or
        $_.Name -like "*.dotnet.*" -or
        $_.Name -like "NuGetScratch*"
    } | ForEach-Object {
        try {
            if ($_.PSIsContainer) {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item $_.FullName -Force -ErrorAction Stop
            }
        } catch {
            Write-Host "Skip: $($_.FullName)" -ForegroundColor DarkYellow
        }
    }

if (-not (Test-IsAdmin)) {
    Write-Host "Run this script as Administrator for complete cleanup." -ForegroundColor Yellow
}

Write-Host "Reset done."

