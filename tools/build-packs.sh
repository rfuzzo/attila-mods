#!/bin/sh
# Build every mod with a `.build-pack` file into packs/<mod>.pack, the committed packs for downloading (see README).
# Runs on macOS and in Git Bash on Windows. Rebuild and commit them when a mod changes.
# usage: tools/build-packs.sh
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
twpack=$repo/tools/twpack/target/release/twpack
[ -x "$twpack" ] || [ -x "$twpack.exe" ] || cargo build --release --manifest-path "$repo/tools/twpack/Cargo.toml"
[ -x "$twpack.exe" ] && twpack=$twpack.exe

# the schema from tools/extract-all.sh, else the one RPFM downloads on Windows
schema=$repo/extracted/schemas/schema_att.ron
[ -f "$schema" ] || schema=${APPDATA:-}/FrodoWazEre/rpfm/config/schemas/schema_att.ron
[ -f "$schema" ] || { echo "no schema_att.ron: run tools/extract-all.sh" >&2; exit 1; }

mkdir -p "$repo/packs"
for marker in "$repo"/mods/*/.build-pack; do
  mod=$(basename "$(dirname "$marker")")
  "$twpack" build "$repo/mods/$mod" -o "$repo/packs/$mod.pack" --schema "$schema" >/dev/null
  echo "built packs/$mod.pack"
done
