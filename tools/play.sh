#!/bin/zsh
# Start the game with TWASE straight into the main menu or a save, without Feral's launcher (the dev loop).
# Builds the region trading, Fireforged fixes and Fireforged encyclopedia packs first, so the game runs the repo's current files. The mods come from tools/mod_list.txt
# (Feral, started without its launcher, sometimes enables none, and a modded save then crashes on load).
# usage: tools/play.sh [--no-deploy] [--feral-mods] [--latest | --load <save name>]
#   --latest       load the newest campaign save
#   --load <name>  load a save by name, with or without ".save", e.g. --load "Western Roman Empire 367 AD Spring"
#   --no-deploy    start with the files already in the game's data folder
#   --feral-mods   use the mods enabled in Feral's mod manager instead of tools/mod_list.txt
# Blocks until the game exits (the launcher restores Feral's preferences then).
set -euo pipefail

repo=${0:A:h:h}
game="$HOME/Library/Application Support/Steam/steamapps/common/Total War Attila"
saves="$HOME/Library/Application Support/Feral Interactive/Total War ATTILA/VFS/User/AppData/Roaming/The Creative Assembly/Attila/save_games"

deploy=true
feral_mods=false
save=""
while (( $# )); do
  case $1 in
    --no-deploy) deploy=false ;;
    --feral-mods) feral_mods=true ;;
    --latest)
      save=$(ls -t "$saves" | grep '\.save$' | head -1)
      [[ -n $save ]] || { echo "no saves in $saves" >&2; exit 1 } ;;
    --load)
      (( $# >= 2 )) || { echo "--load needs a save name" >&2; exit 1 }
      save=${2%.save}.save; shift
      [[ -f "$saves/$save" ]] || { echo "no save \"$save\" in $saves" >&2; exit 1 } ;;
    -h|--help) sed -n '2,12s/^# \{0,1\}//p' $0; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done

if pgrep -f "MacOS/Total War ATTILA" >/dev/null; then
  echo "the game is already running" >&2; exit 1
fi
pgrep -x steam_osx >/dev/null || echo "warning: Steam isn't running, the game needs it" >&2
if [[ -d "$game/TotalWarAttilaData/data/campaigns/main_attila/mods/region_trading_dev" ]]; then
  echo "warning: the dev harness is deployed and will click through the UI (tools/deploy.sh --remove region_trading_dev)" >&2
fi

if $deploy; then
  $repo/tools/deploy.sh region_trading
  $repo/tools/deploy.sh fireforged_fixes
  $repo/tools/deploy.sh fireforged_encyclopedia
fi

args=(--skip-launcher)
$feral_mods || args+=(--mods "$repo/tools/mod_list.txt")
[[ -n $save ]] && args+=(--load "$save") && echo "loading $save"
exec "$game/twase-launch.command" $args
