param(
    [string]$Configuration = "Release",
    [string]$PackageId = "com.norkn.app",
    [string]$ApkPath = "",
    [string]$Serial = "",
    [int]$RetryCount = 5
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$defaultApk = Join-Path $repoRoot "NoRKN.Android\bin\$Configuration\net8.0-android\publish\NoRKN.apk"
if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = $defaultApk
}

$adbLocal = Join-Path $repoRoot "_android_sdk\platform-tools\adb.exe"
$adb = if (Test-Path $adbLocal) { $adbLocal } else { "adb" }

if (-not (Test-Path $ApkPath)) {
    throw "APK not found: $ApkPath"
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args,
        [string]$Serial = "",
        [int]$TimeoutSec = 30
    )

    $allArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        $allArgs += @("-s", $Serial)
    }
    $allArgs += $Args

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $adb `
            -ArgumentList $allArgs `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile

        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            try { $proc.Kill() } catch { }
            return [PSCustomObject]@{
                ExitCode = -1
                Lines    = @("adb timeout after ${TimeoutSec}s")
                Text     = "adb timeout after ${TimeoutSec}s"
                Args     = $allArgs
            }
        }

        $lines = @()
        if (Test-Path $outFile) { $lines += Get-Content $outFile }
        if (Test-Path $errFile) { $lines += Get-Content $errFile }
        $text = ($lines -join "`n").Trim()

        [PSCustomObject]@{
            ExitCode = $proc.ExitCode
            Lines    = $lines
            Text     = $text
            Args     = $allArgs
        }
    }
    finally {
        Remove-Item -Force $outFile, $errFile -ErrorAction SilentlyContinue
    }
}

function Get-AdbDevices {
    $res = Invoke-Adb -Args @("devices")
    $items = @()
    foreach ($line in $res.Lines) {
        if ($line -match "^([\S]+)\s+([\S]+)$" -and $line -notmatch "^List of devices attached") {
            $items += [PSCustomObject]@{
                Serial = $matches[1]
                State  = $matches[2]
            }
        }
    }

    [PSCustomObject]@{
        Raw   = $res
        Items = $items
    }
}

function Ensure-OnlineDevice {
    param(
        [string]$PreferredSerial = "",
        [int]$Attempts = 5
    )

    for ($i = 1; $i -le $Attempts; $i++) {
        $devices = Get-AdbDevices
        $rawText = ($devices.Raw.Lines -join "`n")
        if ($rawText) { Write-Host $rawText }

        $current = $null
        if (-not [string]::IsNullOrWhiteSpace($PreferredSerial)) {
            $current = $devices.Items | Where-Object { $_.Serial -eq $PreferredSerial } | Select-Object -First 1
            if (-not $current) {
                Write-Host "Device '$PreferredSerial' not found (attempt $i/$Attempts)." -ForegroundColor Yellow
            }
        }
        else {
            $current = $devices.Items | Where-Object { $_.State -eq "device" } | Select-Object -First 1
            if (-not $current -and $devices.Items.Count -gt 0) {
                $current = $devices.Items | Select-Object -First 1
            }
        }

        if ($current -and $current.State -eq "device") {
            return $current.Serial
        }

        $statusText = if ($devices.Items.Count -gt 0) {
            ($devices.Items | ForEach-Object { "{0}:{1}" -f $_.Serial, $_.State }) -join ", "
        }
        else {
            "no devices"
        }
        Write-Host "ADB device state is not ready ($statusText). Recovery attempt $i/$Attempts..." -ForegroundColor Yellow

        if ($i -eq 1) {
            $null = Invoke-Adb -Args @("reconnect")
            $null = Invoke-Adb -Args @("reconnect", "offline")
        }
        else {
            $null = Invoke-Adb -Args @("kill-server")
            Start-Sleep -Seconds 1
            $null = Invoke-Adb -Args @("start-server")
            $null = Invoke-Adb -Args @("reconnect", "offline")
        }

        $wait = Invoke-Adb -Args @("wait-for-device") -TimeoutSec 20
        if ($wait.Text) { Write-Host $wait.Text }
        Start-Sleep -Seconds 2
    }

    throw "No authorized Android device found in ONLINE state. Enable USB debugging, set USB mode to File Transfer, reconnect cable, and accept RSA prompt on phone."
}

function Install-Apk {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceSerial,
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [switch]$NoStreaming
    )

    $args = @("install")
    if ($NoStreaming) {
        $args += "--no-streaming"
    }
    $args += @("-r", "-d", "-g", "-t", $FilePath)
    Invoke-Adb -Serial $DeviceSerial -Args $args -TimeoutSec 180
}

function Test-PackageInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceSerial,
        [Parameter(Mandatory = $true)]
        [string]$PackageId
    )

    $res = Invoke-Adb -Serial $DeviceSerial -Args @("shell", "pm", "path", $PackageId)
    return ($res.Text -match "(?m)^package:")
}

function Install-ApkViaPm {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceSerial,
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string]$RemotePath = "/data/local/tmp/norkn-install.apk"
    )

    $push = Invoke-Adb -Serial $DeviceSerial -Args @("push", $FilePath, $RemotePath) -TimeoutSec 300
    if ($push.Text) { Write-Host $push.Text }

    $install = Invoke-Adb -Serial $DeviceSerial -Args @("shell", "pm", "install", "-r", "-d", "-g", "-t", $RemotePath) -TimeoutSec 240
    if ($install.Text) { Write-Host $install.Text }

    $null = Invoke-Adb -Serial $DeviceSerial -Args @("shell", "rm", "-f", $RemotePath) -TimeoutSec 30

    return $install
}

Write-Host "Using adb: $adb"
$startServer = Invoke-Adb -Args @("start-server")
if ($startServer.Text) { Write-Host $startServer.Text }

$deviceSerial = Ensure-OnlineDevice -PreferredSerial $Serial -Attempts $RetryCount
Write-Host "Selected device: $deviceSerial" -ForegroundColor Cyan

Write-Host "Installing: $ApkPath" -ForegroundColor Cyan
$install = Install-Apk -DeviceSerial $deviceSerial -FilePath $ApkPath
$text = $install.Text
Write-Host $text

if (Test-PackageInstalled -DeviceSerial $deviceSerial -PackageId $PackageId) {
    Write-Host "Install completed (package already present after first attempt)." -ForegroundColor Green
    return
}

if ($text -match "device offline" -or $text -match "failed to read copy response: EOF" -or $text -match "protocol fault") {
    Write-Host "ADB transport error during install. Recovering connection and retrying..." -ForegroundColor Yellow
    $null = Invoke-Adb -Args @("kill-server")
    Start-Sleep -Seconds 1
    $null = Invoke-Adb -Args @("start-server")
    $deviceSerial = Ensure-OnlineDevice -PreferredSerial $deviceSerial -Attempts $RetryCount
    $install = Install-Apk -DeviceSerial $deviceSerial -FilePath $ApkPath -NoStreaming
    $text = $install.Text
    Write-Host $text
}

if (($text -match "device offline" -or $text -match "failed to read copy response: EOF" -or $text -match "protocol fault") -or
    (($install.ExitCode -ne 0) -and -not (Test-PackageInstalled -DeviceSerial $deviceSerial -PackageId $PackageId))) {
    Write-Host "Trying fallback install via: adb push + pm install ..." -ForegroundColor Yellow
    $null = Invoke-Adb -Args @("kill-server")
    Start-Sleep -Seconds 1
    $null = Invoke-Adb -Args @("start-server")
    $deviceSerial = Ensure-OnlineDevice -PreferredSerial $deviceSerial -Attempts $RetryCount
    $install = Install-ApkViaPm -DeviceSerial $deviceSerial -FilePath $ApkPath
    $text = $install.Text
}

$hasSuccess = ($text -match "(?m)^\s*Success\s*$" -or $text -match "\bSuccess\b")
$hasInstallFailure = ($text -match "INSTALL_FAILED_" -or $text -match "INSTALL_PARSE_FAILED_" -or $text -match "Failure \[")
if (($hasSuccess -and -not $hasInstallFailure) -or (Test-PackageInstalled -DeviceSerial $deviceSerial -PackageId $PackageId)) {
    Write-Host "Install completed." -ForegroundColor Green
    return
}

if ($text -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE" -or
    $text -match "INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES" -or
    $text -match "INSTALL_FAILED_VERSION_DOWNGRADE") {
    Write-Host "Signature/version conflict with installed app. Reinstalling..." -ForegroundColor Yellow
    $uninstall = Invoke-Adb -Serial $deviceSerial -Args @("uninstall", $PackageId)
    if ($uninstall.Text) { Write-Host $uninstall.Text }

    $retry = Install-Apk -DeviceSerial $deviceSerial -FilePath $ApkPath
    $retryText = $retry.Text
    Write-Host $retryText

    $retryHasSuccess = ($retryText -match "(?m)^\s*Success\s*$" -or $retryText -match "\bSuccess\b")
    $retryHasInstallFailure = ($retryText -match "INSTALL_FAILED_" -or $retryText -match "INSTALL_PARSE_FAILED_" -or $retryText -match "Failure \[")
    if (((-not $retryHasSuccess) -or $retryHasInstallFailure) -and
        -not (Test-PackageInstalled -DeviceSerial $deviceSerial -PackageId $PackageId)) {
        throw "Install failed after reinstall attempt: $retryText"
    }
}
elseif (($install.ExitCode -ne 0 -or $text -notmatch "Success") -and
        -not (Test-PackageInstalled -DeviceSerial $deviceSerial -PackageId $PackageId)) {
    $state = Invoke-Adb -Serial $deviceSerial -Args @("get-state")
    $stateText = if ($state.Text) { $state.Text } else { "unknown" }
    $abi = Invoke-Adb -Serial $deviceSerial -Args @("shell", "getprop", "ro.product.cpu.abi")
    $abiText = if ($abi.Text) { $abi.Text } else { "unknown" }
    throw "Install failed: $text`nADB state: $stateText`nDevice ABI: $abiText`nAPK: $ApkPath"
}

Write-Host "Install completed." -ForegroundColor Green
