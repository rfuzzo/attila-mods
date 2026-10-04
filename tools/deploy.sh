#!/bin/zsh
# Copy a mod from mods/<name>/ into the game's data folder as loose files (the TWASE test loop),
# or remove it again. Loose Lua is read when a campaign loads, so a reload picks up changes.
# usage: tools/deploy.sh [--remove] [mod name, default region_trading]
set -euo pipefail

repo=${0:A:h:h}
data="$HOME/Library/Application Support/Steam/steamapps/common/Total War Attila/TotalWarAttilaData/data"

remove=false
if [[ ${1:-} == --remove ]]; then remove=true; shift; fi
mod=${1:-region_trading}
src=$repo/mods/$mod
[[ -d $src ]] || { echo "no mod at $src" >&2; exit 1 }

# Every file of the mod, relative to its root (the data root).
files=(${(f)"$(cd $src && find . -type f ! -name '.*' | sed 's|^\./||' | sort)"})

if $remove; then
  for f in $files; do rm -f "$data/$f"; done
  # drop the folders the mod created, if they are empty now
  (cd $src && find . -mindepth 1 -type d | sort -r) | while read -r d; do rmdir "$data/${d#./}" 2>/dev/null || true; done
  echo "removed $mod (${#files} files) from $data"
else
  for f in $files; do
    mkdir -p "$data/${f:h}"
    cp "$src/$f" "$data/$f"
  done
  echo "deployed $mod (${#files} files) to $data"
fi
