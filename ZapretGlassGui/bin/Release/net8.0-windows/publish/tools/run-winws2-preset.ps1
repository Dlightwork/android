param(
    [Parameter(Mandatory = $true)]
    [string]$EnginePath,

    [Parameter(Mandatory = $true)]
    [string[]]$PresetFile,

    [string]$BaseDir = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$expandedPresetFiles = New-Object System.Collections.Generic.List[string]
foreach ($pf in $PresetFile) {
    if ([string]::IsNullOrWhiteSpace($pf)) { continue }
    $parts = $pf -split ';'
    foreach ($part in $parts) {
        $p = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        [void]$expandedPresetFiles.Add($p)
    }
}
if ($expandedPresetFiles.Count -eq 0) {
    throw "No preset files provided."
}

function Resolve-PathLike {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$PresetDir,
        [Parameter(Mandatory = $true)][string]$BaseDir
    )

    if ([System.IO.Path]::IsPathRooted($Value)) {
        if (Test-Path -LiteralPath $Value) { return $Value }
        return $null
    }

    $baseCandidate = Join-Path $BaseDir $Value
    if (Test-Path -LiteralPath $baseCandidate) { return $baseCandidate }

    $presetCandidate = Join-Path $PresetDir $Value
    if (Test-Path -LiteralPath $presetCandidate) { return $presetCandidate }

    return $null
}

$engineCandidate = $EnginePath
if (-not (Test-Path -LiteralPath $engineCandidate)) {
    $altEngine = Join-Path $BaseDir $engineCandidate
    if (-not (Test-Path -LiteralPath $altEngine)) {
        throw "Engine not found: $EnginePath"
    }
    $engineCandidate = $altEngine
}
$EnginePath = (Resolve-Path -LiteralPath $engineCandidate).Path

$resolvedPresetFiles = @()
foreach ($pf in $expandedPresetFiles) {
    if (Test-Path -LiteralPath $pf) {
        $resolvedPresetFiles += (Resolve-Path -LiteralPath $pf).Path
        continue
    }
    $inBase = Join-Path $BaseDir $pf
    if (Test-Path -LiteralPath $inBase) {
        $resolvedPresetFiles += (Resolve-Path -LiteralPath $inBase).Path
        continue
    }
    throw "Preset file not found: $pf"
}

$argsList = New-Object System.Collections.Generic.List[string]

foreach ($presetPath in $resolvedPresetFiles) {
    $presetDir = Split-Path -Parent $presetPath
    foreach ($rawLine in Get-Content -LiteralPath $presetPath) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith("#")) { continue }

        $pathRef = $null
        if ($line -match '^--lua-init=@(.+)$') {
            $pathRef = $Matches[1]
        } elseif ($line -match '^--wf-raw-part=@(.+)$') {
            $pathRef = $Matches[1]
        } elseif ($line -match '^--blob=[^:]+:\+?@(.+)$') {
            $pathRef = $Matches[1]
        } elseif ($line -match '^--hostlist=(.+)$') {
            $pathRef = $Matches[1]
        } elseif ($line -match '^--ipset=(.+)$') {
            $pathRef = $Matches[1]
        } elseif ($line -match '^--ipset-exclude=(.+)$') {
            $pathRef = $Matches[1]
        }

        if ($pathRef) {
            $resolvedRef = Resolve-PathLike -Value $pathRef -PresetDir $presetDir -BaseDir $BaseDir
            if (-not $resolvedRef) {
                Write-Host "[skip] Missing reference: $pathRef"
                continue
            }
        }

        [void]$argsList.Add($line)
    }
}

if ($argsList.Count -eq 0) {
    throw "No valid arguments after preset filtering."
}

Write-Host "[*] Engine: $EnginePath"
Write-Host "[*] Presets: $($resolvedPresetFiles -join ', ')"
Write-Host "[*] Effective args: $($argsList.Count)"

$exitCode = 1
Push-Location $BaseDir
try {
    & $EnginePath @argsList
    if ($LASTEXITCODE -ne $null) {
        $exitCode = $LASTEXITCODE
    } else {
        $exitCode = 0
    }
}
finally {
    Pop-Location
}

exit $exitCode
