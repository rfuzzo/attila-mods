#!/bin/zsh
# Unpack the base game and the region trading mods into extracted/ (git-ignored) for grepping and diffing.
# Only text-like content: DB tables and loc as TSV, Lua, UI layouts, XML. Images, models, animations and shaders are skipped.
# Re-run after a game or Workshop update; extracted/ is its own git repo, so `git -C extracted diff` shows what changed.
# usage: tools/extract-all.sh
set -euo pipefail

repo=${0:A:h:h}
twpack=$repo/tools/twpack/target/release/twpack
out=$repo/extracted
data="$HOME/Library/Application Support/Steam/steamapps/common/Total War Attila/TotalWarAttilaData/data"
workshop="$HOME/Library/Application Support/Steam/steamapps/workshop/content/325610"

[[ -x $twpack ]] || cargo build --release --manifest-path $repo/tools/twpack/Cargo.toml
[[ -f $out/schemas/schema_att.ron ]] || { echo "missing $out/schemas/schema_att.ron (from rpfm-schemas)" >&2; exit 1 }

skip=(
  -x '*.png' -x '*.dds' -x '*.tga' -x '*.jpg' -x '*.psd' -x '*.texture_array'
  -x '*.rigid_model_v2*' -x '*.anim' -x '*.fxc'
  -x '*.ppd' -x '*.dat' -x '*.campaign_tree_list'
  -x animations/ -x animations_cinematic/ -x fxc/ -x terrain/ -x movies/ -x weather/ -x variantmeshes/
  -x wind_level_ -x ui/portraits/
)

# extract <pack> <destination relative to extracted/>
extract() {
  print "== $2"
  rm -rf $out/$2
  $twpack extract $1 -o $out/$2 $skip
}

extract "$data/data.pack" game/data
extract "$data/belisarius.pack" game/belisarius
extract "$data/charlemagne.pack" game/charlemagne
extract "$data/localisation/en/local_en.pack" game/local_en

extract "$workshop/2649271551/@Fireforged-Empire_1.pack" fireforged/1
extract "$workshop/2882854931/@Fireforged-Empire_ballast.pack" fireforged/ballast
# @Fireforged-Empire_2.pack (2649270391) only holds models and textures.

extract "$workshop/2875210346/maga_reloaded.pack" rtr

# Pack timestamps, so a diff after an update can say which pack changed.
{
  for pack in "$data"/{data,belisarius,charlemagne}.pack "$data/localisation/en/local_en.pack" \
      "$workshop"/2649271551/*.pack "$workshop"/2882854931/*.pack "$workshop"/2875210346/*.pack; do
    print "$(stat -f '%Sm %z' -t '%Y-%m-%d %H:%M' $pack) ${pack:t}"
  done
} > $out/PACKS.txt

[[ -d $out/.git ]] || git -C $out init -q
print "done, see $out/PACKS.txt; commit a snapshot with: git -C extracted add -A && git -C extracted commit -m <message>"
