#!/bin/zsh
# Copy a mod from mods/<name>/ into the game's data folder as loose files (the TWASE test loop),
# or remove it again. Loose Lua is read when a campaign loads, so a reload picks up changes.
# A mod with a `.build-pack` file is built into data/<mod>.pack (`twpack build`) instead of copied loose: the game only
# takes UI layouts from packs. Add `mod "<mod>.pack";` to tools/mod_list.txt to load it. The pack is also linked into
# Feral's VFS/Local/local_mods/<mod>/, so it shows up in Feral's mod manager (switch it on there).
# UI layouts written as text (`*.uic.yml`, see docs/UI-FORMAT.md) are encoded to binary layouts on the way (path without the suffix).
# A pack mod with a `.generate` script gets the files it writes too (`.generate <build folder> <twpack>`), for files
# that can't be in git because they're made from the game's or other mods' data.
# usage: tools/deploy.sh [--remove] [mod name, default region_trading]
set -euo pipefail

repo=${0:A:h:h}
data="$HOME/Library/Application Support/Steam/steamapps/common/Total War Attila/TotalWarAttilaData/data"
local_mods="$HOME/Library/Application Support/Feral Interactive/Total War ATTILA/VFS/Local/local_mods"

remove=false
if [[ ${1:-} == --remove ]]; then remove=true; shift; fi
mod=${1:-region_trading}
src=$repo/mods/$mod
[[ -d $src ]] || { echo "no mod at $src" >&2; exit 1 }

twpack=$repo/tools/twpack/target/release/twpack
# The path a mod file ends up at in the data folder.
target() { print -r -- "${1%.uic.yml}" }

# Every file of the mod, relative to its root (the data root).
files=(${(f)"$(cd $src && find . -type f ! -name '.*' | sed 's|^\./||' | sort)"})

if [[ -f $src/.build-pack ]]; then
  [[ -x $twpack ]] || cargo build --release --manifest-path $repo/tools/twpack/Cargo.toml
  if $remove; then
    rm -f "$data/$mod.pack"; rm -rf "$local_mods/$mod"; echo "removed $mod.pack from $data and Feral's mod manager"
  else
    build=$src
    if [[ -x $src/.generate ]]; then
      build=$(mktemp -d)
      trap 'rm -rf $build' EXIT
      cp -R $src/ $build/
      $src/.generate $build $twpack
      files=(${(f)"$(cd $build && find . -type f ! -name '.*' | sed 's|^\./||' | sort)"})
    fi
    $twpack build $build -o "$data/$mod.pack" >/dev/null && echo "built $mod.pack (${#files} files) in $data"
    # Feral's mod manager lists local_mods/<folder>/<name>.pack (one folder per mod) next to the Workshop items
    mkdir -p "$local_mods/$mod" && ln -sfn "$data/$mod.pack" "$local_mods/$mod/$mod.pack"
  fi
  exit 0
fi

if $remove; then
  for f in $files; do rm -f "$data/$(target $f)"; done
  # drop the folders the mod created, if they are empty now
  (cd $src && find . -mindepth 1 -type d | sort -r) | while read -r d; do rmdir "$data/${d#./}" 2>/dev/null || true; done
  echo "removed $mod (${#files} files) from $data"
else
  if (( ${#files:#*.uic.yml} != ${#files} )) && [[ ! -x $twpack ]]; then
    cargo build --release --manifest-path $repo/tools/twpack/Cargo.toml
  fi
  for f in $files; do
    t=$(target $f)
    mkdir -p "$data/${t:h}"
    if [[ $f == *.uic.yml ]]; then $twpack ui import "$src/$f" -o "$data/$t"; else cp "$src/$f" "$data/$t"; fi
  done
  echo "deployed $mod (${#files} files) to $data"
fi
