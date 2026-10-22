# Paths shared by the Windows scripts (dot-source it: `. $PSScriptRoot\paths.ps1`).
# The game and the Workshop items are looked up in Steam's library folders; $env:ATTILA_GAME overrides the game folder.

$Repo = Split-Path $PSScriptRoot -Parent
$AppId = '325610'

# Every Steam library folder, from the registry and steamapps\libraryfolders.vdf.
function Get-SteamLibraries {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { $steam = 'C:\Program Files (x86)\Steam' }
    $libs = @($steam -replace '/', '\')
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $libs += $m.Groups[1].Value -replace '\\\\', '\'
        }
    }
    $libs | Select-Object -Unique
}

function Get-GameDir {
    if ($env:ATTILA_GAME) { return $env:ATTILA_GAME }
    foreach ($lib in Get-SteamLibraries) {
        $dir = Join-Path $lib 'steamapps\common\Total War Attila'
        if (Test-Path (Join-Path $dir 'Attila.exe')) { return $dir }
    }
    throw 'Total War: ATTILA not found in any Steam library (set $env:ATTILA_GAME to the game folder)'
}

# The Workshop item folders (steamapps\workshop\content\325610\<id>) of every library.
function Get-WorkshopItems {
    foreach ($lib in Get-SteamLibraries) {
        $dir = Join-Path $lib "steamapps\workshop\content\$AppId"
        if (Test-Path $dir) { Get-ChildItem $dir -Directory }
    }
}

# twpack.exe, built on first use.
function Get-Twpack {
    $exe = Join-Path $Repo 'tools\twpack\target\release\twpack.exe'
    if (-not (Test-Path $exe)) {
        cargo build --release --manifest-path (Join-Path $Repo 'tools\twpack\Cargo.toml')
        if ($LASTEXITCODE) { throw 'building twpack failed' }
    }
    $exe
}

# The DB schema for `twpack build`: extracted\schemas (tools/extract-all.sh) or the one RPFM downloads.
function Get-Schema {
    foreach ($s in (Join-Path $Repo 'extracted\schemas\schema_att.ron'),
                   (Join-Path $env:APPDATA 'FrodoWazEre\rpfm\config\schemas\schema_att.ron')) {
        if (Test-Path $s) { return $s }
    }
    throw 'no schema_att.ron: run tools/extract-all.sh, or let RPFM download its schemas'
}
