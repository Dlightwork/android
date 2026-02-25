# Download WinDivert SDK
$ErrorActionPreference = "Stop"

$Url = "https://reqrypt.org/download/WinDivert-2.2.2-A.zip"
$ZipFile = "WinDivert-2.2.2-A.zip"
$ExtractPath = "WinDivert-2.2.2-A"

Write-Host "Downloading WinDivert SDK..." -ForegroundColor Cyan
Write-Host "URL: $Url"

# Download
Invoke-WebRequest -Uri $Url -OutFile $ZipFile -UseBasicParsing
Write-Host "Downloaded: $ZipFile" -ForegroundColor Green

# Extract
Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $ZipFile -DestinationPath "." -Force
Write-Host "Extracted to: $ExtractPath" -ForegroundColor Green

# Copy files to project root
Write-Host "Copying SDK files to project..." -ForegroundColor Cyan
Copy-Item "$ExtractPath\x64\WinDivert.lib" "." -Force
Copy-Item "$ExtractPath\include\windivert.h" "." -Force
Copy-Item "$ExtractPath\x64\WinDivert.dll" "." -Force
Copy-Item "$ExtractPath\x64\WinDivert64.sys" "." -Force

Write-Host "SDK files copied successfully!" -ForegroundColor Green

# Cleanup
Remove-Item $ZipFile -Force
Remove-Item $ExtractPath -Recurse -Force
Write-Host "Cleanup complete" -ForegroundColor Green

Write-Host ""
Write-Host "WinDivert SDK ready!" -ForegroundColor Green
Write-Host "Now run: build.bat" -ForegroundColor Yellow

