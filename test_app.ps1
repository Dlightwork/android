$ErrorActionPreference = "Continue"
$errLog = "$env:TEMP\dotnet_err.log"
$outLog = "$env:TEMP\dotnet_out.log"

$proc = Start-Process "C:\Users\User\OneDrive\Рабочий стол\project2\ZapretGlassGui\bin\Release\net8.0-windows\NoRKN.exe" -PassThru -RedirectStandardError $errLog -RedirectStandardOutput $outLog -WindowStyle Hidden

Start-Sleep -Seconds 5

if (Test-Path $errLog) { 
    Write-Host "=== STDERR ===" 
    Get-Content $errLog 
}

if (Test-Path $outLog) { 
    Write-Host "=== STDOUT ===" 
    Get-Content $outLog 
}

if (!$proc.HasExited) { 
    Write-Host "Process is running with PID: $($proc.Id)"
    Stop-Process $proc.Id -Force 
} else { 
    Write-Host "Process exited with code: $($proc.ExitCode)" 
}
