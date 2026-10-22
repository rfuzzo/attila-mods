<#
.SYNOPSIS
Windows version of tools/play.sh: start the game with TWASE and the mods in tools\mod_list.txt, without the game's launcher.
.DESCRIPTION
Builds the region trading and Fireforged fixes packs first, so the game runs the repo's current files. TWASE is loaded by
its winmm.dll proxy in the game folder. The mod list is written to <game>\attila_mods.txt with an `add_working_directory`
line for every pack that comes from the Workshop (the game takes the list as its argument, like Runcher does).
Loading a save straight away (play.sh --latest / --load) needs TWASE's macOS launcher and isn't there on Windows.
Blocks until the game exits.
.EXAMPLE
tools\play.ps1
tools\play.ps1 -NoDeploy -ModList my_list.txt
#>
param(
    [switch]$NoDeploy,
    [string]$ModList = "$PSScriptRoot\mod_list.txt"
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\paths.ps1"

$game = Get-GameDir
if (Get-Process Attila -ErrorAction SilentlyContinue) { throw 'the game is already running' }
if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { Write-Warning "Steam isn't running, the game needs it" }
if (-not (Test-Path (Join-Path $game 'TWASE\TWASE.dll'))) { Write-Warning "TWASE isn't installed in $game, the mods' scripts won't load" }
if (Test-Path (Join-Path $game 'data\campaigns\main_attila\mods\region_trading_dev')) {
    Write-Warning 'the dev harness is deployed and will click through the UI (tools\deploy.ps1 -Remove region_trading_dev)'
}

if (-not $NoDeploy) {
    & "$PSScriptRoot\deploy.ps1" region_trading
    & "$PSScriptRoot\deploy.ps1" fireforged_fixes
}

# Packs in data\ load as they are; the others are looked up in the Workshop folders.
$workshop = @(Get-WorkshopItems)
$dirs = [System.Collections.Generic.List[string]]::new()
$mods = foreach ($line in Get-Content $ModList) {
    if ($line -notmatch '^\s*mod\s+"([^"]+)"\s*;') { continue }
    $pack = $Matches[1]
    if (Test-Path (Join-Path $game "data\$pack")) { $line; continue }
    $item = $workshop | Where-Object { Test-Path (Join-Path $_.FullName $pack) } | Select-Object -First 1
    if (-not $item) { Write-Warning "$pack is neither in data\ nor in a Workshop item, leaving it out"; continue }
    $dir = $item.FullName -replace '\\', '/'
    if (-not $dirs.Contains($dir)) { $dirs.Add($dir) }
    $line
}
$list = Join-Path $game 'attila_mods.txt'
Set-Content $list -Encoding ascii -Value (@($dirs | ForEach-Object { "add_working_directory `"$_`";" }) + $mods)
"mods: $(@($mods).Count) packs from $ModList"

Start-Process (Join-Path $game 'Attila.exe') -ArgumentList 'attila_mods.txt;' -WorkingDirectory $game -Wait
