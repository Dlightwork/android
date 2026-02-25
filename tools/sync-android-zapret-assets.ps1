param(
    [switch]$Quiet,
    [switch]$SkipLinkRepos,
    [switch]$SkipRepoFetch,
    [string]$RefsRoot = "_tmp_refs",
    [string]$WindowsBuildRoot = "ZapretGlassGui\bin\Release\net8.0-windows"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$androidZapretRoot = Join-Path $repoRoot "NoRKN.Android\zapret"

if (-not (Test-Path $androidZapretRoot)) {
    throw "Android zapret directory not found: $androidZapretRoot"
}

function Write-Info([string]$message) {
    if (-not $Quiet) {
        Write-Host $message
    }
}

function Reset-Directory([string]$path) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force
    }
    New-Item -Path $path -ItemType Directory | Out-Null
}

function Copy-FilteredTree(
    [string]$sourceRoot,
    [string]$destinationRoot,
    [string[]]$allowedExtensions
) {
    if (-not (Test-Path $sourceRoot)) {
        Write-Info "skip missing source: $sourceRoot"
        return 0
    }

    $copied = 0
    $files = Get-ChildItem -Path $sourceRoot -Recurse -File | Where-Object {
        $allowedExtensions -contains $_.Extension.ToLowerInvariant()
    }

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
        $targetPath = Join-Path $destinationRoot $relative
        $targetDir = Split-Path -Path $targetPath -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path $file.FullName -Destination $targetPath -Force
        $copied++
    }

    return $copied
}

function Ensure-GitRepo([string]$url, [string]$path, [switch]$skipFetch) {
    if (Test-Path $path) {
        if (-not $skipFetch) {
            try {
                git -C $path pull --ff-only | Out-Null
            } catch {
                Write-Info "warning: failed to update $path"
            }
        }
        return $true
    }

    try {
        git clone --depth 1 $url $path | Out-Null
        return $true
    } catch {
        Write-Info "warning: failed to clone $url"
        return $false
    }
}

Write-Info "Syncing zapret assets into NoRKN.Android..."

$targetLists = Join-Path $androidZapretRoot "lists"
$targetLua = Join-Path $androidZapretRoot "lua"
$targetPresets = Join-Path $androidZapretRoot "presets"
$targetFilters = Join-Path $androidZapretRoot "windivert.filter"

Reset-Directory $targetLists
Reset-Directory $targetLua
Reset-Directory $targetPresets
Reset-Directory $targetFilters

# Keep only current root-level .bin payload files.
Get-ChildItem -Path $androidZapretRoot -File -Filter *.bin -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

$rootBinCopied = 0
Get-ChildItem -Path $repoRoot -File -Filter *.bin | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination (Join-Path $androidZapretRoot $_.Name) -Force
    $rootBinCopied++
}

# Main project sources
$listsCopied = Copy-FilteredTree -sourceRoot (Join-Path $repoRoot "lists") -destinationRoot $targetLists -allowedExtensions @(".txt")
$luaCopied = Copy-FilteredTree -sourceRoot (Join-Path $repoRoot "lua") -destinationRoot $targetLua -allowedExtensions @(".lua", ".txt")
$presetsCopied = Copy-FilteredTree -sourceRoot (Join-Path $repoRoot "presets") -destinationRoot $targetPresets -allowedExtensions @(".args")
$filtersCopied = Copy-FilteredTree -sourceRoot (Join-Path $repoRoot "windivert.filter") -destinationRoot $targetFilters -allowedExtensions @(".txt")

# Root-level list-like txt files.
$legacyRootDir = Join-Path $targetLists "root"
New-Item -Path $legacyRootDir -ItemType Directory -Force | Out-Null
$rootTxtCopied = 0
$rootTxtFiles = Get-ChildItem -Path $repoRoot -File -Filter *.txt |
    Where-Object { $_.Name -notmatch '^(error|help|test_out|android_build)\.txt$' }
foreach ($file in $rootTxtFiles) {
    Copy-Item -Path $file.FullName -Destination (Join-Path $legacyRootDir $file.Name) -Force
    $rootTxtCopied++
}

# Windows preset profiles from bat/*.txt -> presets/windows/*.args
$windowsPresetDir = Join-Path $targetPresets "windows"
New-Item -Path $windowsPresetDir -ItemType Directory -Force | Out-Null
$windowsPresetsCopied = 0
if (Test-Path (Join-Path $repoRoot "bat")) {
    Get-ChildItem -Path (Join-Path $repoRoot "bat") -File -Filter *.txt | ForEach-Object {
        $targetName = [System.IO.Path]::ChangeExtension($_.Name, ".args")
        $targetPath = Join-Path $windowsPresetDir $targetName
        Copy-Item -Path $_.FullName -Destination $targetPath -Force
        $windowsPresetsCopied++
    }
}

$zapret2LuaCopied = 0
$zapret2ListsCopied = 0
$zaprettAppMetaCopied = 0
$windowsOverlayListsCopied = 0
$windowsOverlayPresetCopied = 0

$windowsBuildPath = if ([System.IO.Path]::IsPathRooted($WindowsBuildRoot)) {
    $WindowsBuildRoot
} else {
    Join-Path $repoRoot $WindowsBuildRoot
}

if (Test-Path $windowsBuildPath) {
    $windowsListsPath = Join-Path $windowsBuildPath "lists"
    $overlayListFiles = @(
        "_auto_hostlist.txt",
        "_auto_ipset.txt",
        "list-roblox.txt",
        "ipset-roblox.txt",
        "roblox_domains.txt",
        "roblox_ips.txt",
        "youtube.txt",
        "youtube_domains.txt",
        "ipset-youtube.txt"
    )

    foreach ($name in $overlayListFiles) {
        $src = Join-Path $windowsListsPath $name
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination (Join-Path $targetLists $name) -Force
            $windowsOverlayListsCopied++
        }
    }

    $windowsPreset = Join-Path $windowsBuildPath "presets\all_tcp_udp_multisplit_sni.args"
    if (Test-Path $windowsPreset) {
        Copy-Item -Path $windowsPreset -Destination (Join-Path $targetPresets "all_tcp_udp_multisplit_sni.args") -Force
        $windowsOverlayPresetCopied = 1
    }
}

if (-not $SkipLinkRepos) {
    $refsPath = if ([System.IO.Path]::IsPathRooted($RefsRoot)) { $RefsRoot } else { Join-Path $repoRoot $RefsRoot }
    New-Item -Path $refsPath -ItemType Directory -Force | Out-Null

    $zapret2Path = Join-Path $refsPath "zapret2"
    $zaprettAppPath = Join-Path $refsPath "zaprett-app"

    $hasZapret2 = Ensure-GitRepo -url "https://github.com/bol-van/zapret2" -path $zapret2Path -skipFetch:$SkipRepoFetch
    $hasZaprettApp = Ensure-GitRepo -url "https://github.com/CherretGit/zaprett-app" -path $zaprettAppPath -skipFetch:$SkipRepoFetch

    if ($hasZapret2) {
        $zapret2LuaDir = Join-Path $targetLua "upstream-zapret2"
        $zapret2ListDir = Join-Path $targetLists "upstream-zapret2"
        New-Item -Path $zapret2LuaDir -ItemType Directory -Force | Out-Null
        New-Item -Path $zapret2ListDir -ItemType Directory -Force | Out-Null

        $zapret2LuaCopied = Copy-FilteredTree `
            -sourceRoot (Join-Path $zapret2Path "lua") `
            -destinationRoot $zapret2LuaDir `
            -allowedExtensions @(".lua", ".txt")

        $customListsPath = Join-Path $zapret2Path "blockcheck2.d\custom"
        if (Test-Path $customListsPath) {
            $customLists = Get-ChildItem -Path $customListsPath -File -Filter *.txt
            foreach ($file in $customLists) {
                Copy-Item -Path $file.FullName -Destination (Join-Path $zapret2ListDir $file.Name) -Force
                $zapret2ListsCopied++
            }
        }

        $excludeDefault = Join-Path $zapret2Path "ipset\zapret-hosts-user-exclude.txt.default"
        if (Test-Path $excludeDefault) {
            Copy-Item -Path $excludeDefault -Destination (Join-Path $zapret2ListDir "zapret-hosts-user-exclude.txt") -Force
            $zapret2ListsCopied++
        }
    }

    if ($hasZaprettApp) {
        # zaprett-app stores strategies in a remote repo at runtime. Keep link metadata inside presets.
        $metaDir = Join-Path $targetPresets "upstream-zaprett-app"
        New-Item -Path $metaDir -ItemType Directory -Force | Out-Null
        $metaFile = Join-Path $metaDir "source-links.args"
        @(
            "# Source links imported during sync:",
            "# - https://github.com/CherretGit/zaprett-app",
            "# - https://github.com/bol-van/zapret2",
            "# Windows profiles are mirrored from /bat/*.txt into presets/windows/*.args"
        ) | Set-Content -Path $metaFile -Encoding UTF8
        $zaprettAppMetaCopied = 1
    }
}

Write-Info "Sync complete."
Write-Info "  root .bin:                $rootBinCopied"
Write-Info "  lists:                    $listsCopied"
Write-Info "  lua:                      $luaCopied"
Write-Info "  presets:                  $presetsCopied"
Write-Info "  filters:                  $filtersCopied"
Write-Info "  root txt lists:           $rootTxtCopied"
Write-Info "  windows profiles (.args): $windowsPresetsCopied"
Write-Info "  windows overlay lists:    $windowsOverlayListsCopied"
Write-Info "  windows overlay preset:   $windowsOverlayPresetCopied"
Write-Info "  zapret2 lua:              $zapret2LuaCopied"
Write-Info "  zapret2 lists:            $zapret2ListsCopied"
Write-Info "  zaprett-app metadata:     $zaprettAppMetaCopied"
