<#
.SYNOPSIS
Windows version of tools/deploy.sh: copy a mod from mods\<name>\ into the game's data folder as loose files, or remove it again.
.DESCRIPTION
Loose Lua is read when a campaign loads, so a reload picks up changes. A mod with a `.build-pack` file is built into
data\<mod>.pack (`twpack build`) instead of copied loose: the game only takes UI layouts from packs. tools\play.ps1 loads
the packs named in tools\mod_list.txt; the game's own launcher lists every pack in data\ too.
UI layouts written as text (`*.uic.yml`, see docs/UI-FORMAT.md) are encoded to binary layouts on the way (path without the suffix).
.EXAMPLE
tools\deploy.ps1 fireforged_fixes
tools\deploy.ps1 -Remove region_trading_dev
#>
param(
    [switch]$Remove,
    [string]$Mod = 'region_trading'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\paths.ps1"

$data = Join-Path (Get-GameDir) 'data'
$src = Join-Path $Repo "mods\$Mod"
if (-not (Test-Path $src -PathType Container)) { throw "no mod at $src" }

# Every file of the mod, relative to its root (the data root).
$files = @(Get-ChildItem $src -Recurse -File | Where-Object Name -notlike '.*' |
    ForEach-Object { $_.FullName.Substring($src.Length + 1) } | Sort-Object)
# The path a mod file ends up at in the data folder.
function Target($f) { Join-Path $data ($f -replace '\.uic\.yml$', '') }

if (Test-Path (Join-Path $src '.build-pack')) {
    $pack = Join-Path $data "$Mod.pack"
    if ($Remove) {
        Remove-Item $pack -ErrorAction SilentlyContinue
        "removed $Mod.pack from $data"
    } else {
        & (Get-Twpack) build $src -o $pack --schema (Get-Schema) | Out-Null
        if ($LASTEXITCODE) { throw "building $Mod.pack failed" }
        "built $Mod.pack ($($files.Count) files) in $data"
    }
    exit 0
}

if ($Remove) {
    foreach ($f in $files) { Remove-Item (Target $f) -ErrorAction SilentlyContinue }
    # drop the folders the mod created, if they are empty now
    Get-ChildItem $src -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
        $d = Join-Path $data $_.FullName.Substring($src.Length + 1)
        if ((Test-Path $d) -and -not (Get-ChildItem $d -Force)) { Remove-Item $d }
    }
    "removed $Mod ($($files.Count) files) from $data"
} else {
    foreach ($f in $files) {
        $t = Target $f
        New-Item -ItemType Directory -Force (Split-Path $t) | Out-Null
        if ($f -like '*.uic.yml') {
            & (Get-Twpack) ui import (Join-Path $src $f) -o $t
            if ($LASTEXITCODE) { throw "encoding $f failed" }
        } else {
            Copy-Item (Join-Path $src $f) $t
        }
    }
    "deployed $Mod ($($files.Count) files) to $data"
}
