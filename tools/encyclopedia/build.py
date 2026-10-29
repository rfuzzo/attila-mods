#!/usr/bin/env python3
"""Build the Fireforged Empire encyclopedia (a static site in encyclopedia/) from the game and mod data.

Reads the git-ignored extracted/ folder (tools/extract-all.sh) and the unit card images in extracted/icons/
(extracted here on the first run with twpack). Writes encyclopedia/: the site from tools/encyclopedia/site/, the
unit data as JSON and the unit cards as JPEG. The game links entries as <base>#/unit/<main unit key>; the site
routes on location.hash (tools/encyclopedia/site/app.js).

usage: tools/encyclopedia/build.py [--no-images]
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import cultures  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
EXTRACTED = REPO / "extracted"
OUT = REPO / "encyclopedia"
SITE = Path(__file__).parent / "site"
TWPACK = REPO / "tools/twpack/target/release/twpack"
GAME_DATA = Path.home() / "Library/Application Support/Steam/steamapps/common/Total War Attila/TotalWarAttilaData/data"
WORKSHOP = Path.home() / "Library/Application Support/Steam/steamapps/workshop/content/325610"
FIREFORGED_PACK = WORKSHOP / "2649271551/@Fireforged-Empire_1.pack"

# Pack roots in extracted/, highest priority first: mod packs override the DLC packs, which override data.pack.
DB_ROOTS = ["fireforged/ballast", "fireforged/1", "game/charlemagne", "game/belisarius", "game/data"]
LOC_ROOTS = ["fireforged/ballast/text", "fireforged/1/text", "game/local_en/text"]
ICON_ROOTS = ["icons/fireforged", "icons/game"]
# multiplayer / test factions that share military groups with real ones
PLACEHOLDER_FACTION = re.compile(r"_(blue|red|green|yellow|white|black|purple|orange)$")


# --- the game's file system and tables -----------------------------------------------------------------------

def merged_files(roots, folder):
    """Files under <root>/<folder> of all roots. A file in a higher priority root hides the file with the same path
    in lower ones (that is how mods replace vanilla tables). Sorted as the game loads them: by pack priority, then by
    file name, so `_rex_main_units` comes before `main_units`."""
    seen = {}
    for priority, root in enumerate(roots):
        base = EXTRACTED / root
        if not (base / folder).is_dir():
            continue
        for path in sorted((base / folder).rglob("*.tsv")):
            rel = path.relative_to(base).as_posix().removesuffix(".tsv")
            seen.setdefault(rel, (priority, path.name, path))
    return [path for _, _, path in sorted(seen.values(), key=lambda v: (v[0], v[1]))]


def read_tsv(path):
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    header = lines[0].split("\t")
    # line 2 is twpack's / RPFM's "#table;version;path" marker
    return [dict(zip(header, line.split("\t"))) for line in lines[2:] if line]


def table(name, key=None):
    """Rows of a DB table. With `key` (a column name or tuple of names) the first row of each key wins, as in the
    game; without it all rows are kept (junction tables), exact duplicates dropped."""
    rows, seen = [], set()
    for path in merged_files(DB_ROOTS, f"db/{name}_tables"):
        for row in read_tsv(path):
            if key is None:
                ident = tuple(sorted(row.items()))
            elif isinstance(key, tuple):
                ident = tuple(row.get(k) for k in key)
            else:
                ident = row.get(key)
            if ident in seen:
                continue
            seen.add(ident)
            rows.append(row)
    return rows


def by(rows, column):
    return {row[column]: row for row in rows}


def load_loc():
    loc = {}
    for path in merged_files(LOC_ROOTS, "db"):
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines()[2:]:
            parts = line.split("\t")
            if len(parts) >= 2:
                loc.setdefault(parts[0], parts[1])
    return loc


def num(value, default=0):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return int(number) if number == int(number) else round(number, 2)


# --- unit cards ------------------------------------------------------------------------------------------------

def extract_icons():
    """Unit card PNGs of data.pack and Fireforged into extracted/icons/ (once; delete the folder to refresh)."""
    targets = [(GAME_DATA / "data.pack", "icons/game"), (FIREFORGED_PACK, "icons/fireforged")]
    for pack, dest in targets:
        if (EXTRACTED / dest).is_dir():
            continue
        if not pack.is_file():
            print(f"warning: {pack} not found, no unit cards from it", file=sys.stderr)
            continue
        print(f"extracting unit cards from {pack.name}")
        subprocess.run([str(TWPACK), "extract", str(pack), "-o", str(EXTRACTED / dest), "ui/units/icons/*"],
                       check=True, stdout=subprocess.DEVNULL)


def icon_path(name):
    for root in ICON_ROOTS:
        path = EXTRACTED / root / "ui/units/icons" / f"{name}.png"
        if path.is_file():
            return path
    return None


def convert_icon(source, name):
    """PNG card -> encyclopedia/img/units/<name>.jpg (JPEG flattens the transparency onto white, the card colour)."""
    dest = OUT / "img/units" / f"{name}.jpg"
    if dest.is_file() and dest.stat().st_mtime >= source.stat().st_mtime:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "82", str(source), "--out", str(dest)],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# --- units -----------------------------------------------------------------------------------------------------

def split_title(text):
    """'Title||Description' (abilities, attributes) -> (title, description)."""
    title, _, description = (text or "").partition("||")
    return title.strip(), description.strip()


def campaign_of(key):
    if key.startswith("cha_"):
        return "cha"
    if key.startswith("bel_"):
        return "bel"
    return "main"


def build_units(loc, images):
    main_units = table("main_units", "unit")
    land_units = by(table("land_units", "key"), "key")
    melee = by(table("melee_weapons", "key"), "key")
    missile = by(table("missile_weapons", "key"), "key")
    projectiles = by(table("projectiles", "key"), "key")
    armours = by(table("unit_armour_types", "key"), "key")
    shields = by(table("unit_shield_types", "key"), "key")
    mounts = by(table("mounts", "key"), "key")
    entities = by(table("battle_entities", "key"), "key")
    factions = table("factions", "key")

    abilities = {}
    for row in table("land_units_to_unit_abilites_junctions"):
        abilities.setdefault(row["land_unit"], []).append(row["ability"])
    attributes = {}
    for row in table("unit_attributes_to_groups_junctions"):
        attributes.setdefault(row["attribute_group"], []).append(row["attribute"])

    # unit -> factions, through the military groups (factions_tables.military_group)
    groups = {}
    for row in table("units_to_groupings_military_permissions"):
        groups.setdefault(row["unit"], set()).add(row["military_group"])
    factions_by_group = {}
    for row in factions:
        if row.get("military_group") and row.get("is_rebel") != "true" and not PLACEHOLDER_FACTION.search(row["key"]):
            factions_by_group.setdefault(row["military_group"], []).append(row["key"])

    # unit -> building levels that recruit it
    buildings = {}
    for row in table("building_units_allowed"):
        # the `enabled` column reads "false" in the rows the game uses too, so it isn't a switch
        buildings.setdefault(row["unit"], set()).add(row["building"])
    # other ways to get a unit: mercenary pools, garrisons (armed citizenry), units only one faction may recruit,
    # and the armies Fireforged's campaign scripts spawn (unit keys in its Lua)
    mercenaries = {row["unit_record"] for row in table("mercenary_unit_groups", "key")}
    garrison = {row["unit"] for row in table("armed_citizenry_units_to_unit_groups_junctions")}
    exclusive = {}
    for row in table("units_to_exclusive_faction_permissions"):
        if row.get("allowed") == "true":
            exclusive.setdefault(row["key"], set()).add(row["faction"])
    scripted = set()
    for path in (EXTRACTED / "fireforged/1/campaigns").rglob("*.lua"):
        for quoted in re.findall(r'"([a-z0-9_,]+)"', path.read_text(encoding="cp1251", errors="replace")):
            scripted.update(quoted.split(","))

    building_names = {}
    for key, text in loc.items():
        if key.startswith("building_culture_variants_name_") and text:
            building_names.setdefault(key[len("building_culture_variants_name_"):], text)

    def building_name(level):
        if level in building_names:
            return building_names[level]
        # culture variants are keyed <level><culture...>; take the first that starts with the level key
        for key, text in building_names.items():
            if key.startswith(level):
                return text
        return level

    cards = {}
    for row in table("unit_variants"):
        if row.get("unit_card"):
            cards.setdefault(row["unit"], row["unit_card"])

    index, details = [], {}
    for mu in main_units:
        key = mu["unit"]
        lu = land_units.get(mu.get("land_unit", ""))
        if mu.get("is_naval") == "true" or not lu:
            continue  # naval units have no land unit card; the game links them too, the site says so

        name = loc.get(f"land_units_onscreen_name_{lu['key']}") or key
        culture = cultures.culture_of(key)

        card = None
        for candidate in (cards.get(lu["key"]), cards.get(key), key, lu["key"]):
            if candidate and icon_path(candidate):
                card = candidate
                break
        if card and images:
            convert_icon(icon_path(card), card)

        weapon = melee.get(lu.get("primary_melee_weapon", ""), {})
        armour = armours.get(lu.get("armour", ""), {})
        shield = shields.get(lu.get("shield", ""), {})
        entity = entities.get(lu.get("man_entity", ""), {})
        mount = mounts.get(lu.get("mount", ""), {})
        mount_entity = entities.get(mount.get("entity", ""), {})
        speed_entity = mount_entity or entity

        stats = {
            "melee_attack": num(lu.get("melee_attack")),
            "melee_defence": num(lu.get("melee_defence")),
            "shield_defence": num(shield.get("shield_defence_value")),
            "charge_bonus": num(lu.get("charge_bonus")),
            "weapon_damage": num(weapon.get("damage")),
            "weapon_ap_damage": num(weapon.get("ap_damage")),
            "bonus_v_infantry": num(weapon.get("bonus_v_infantry")),
            "bonus_v_cavalry": num(weapon.get("bonus_v_cavalry")),
            "armour": num(armour.get("armour_value")),
            "shield_armour": num(shield.get("shield_armour_value")),
            "missile_block": num(shield.get("missile_block_chance")),
            "morale": num(lu.get("morale")),
            "hit_points": num(entity.get("hit_points")) + num(lu.get("bonus_hit_points")),
            "mount_hit_points": num(mount_entity.get("hit_points")) if mount_entity else 0,
            "speed": num(speed_entity.get("run_speed")),
            "accuracy": num(lu.get("accuracy")),
        }
        missile_weapon = missile.get(lu.get("primary_missile_weapon", ""))
        if missile_weapon:
            projectile = projectiles.get(missile_weapon.get("default_projectile", ""), {})
            stats.update({
                "missile_damage": num(projectile.get("damage")),
                "missile_ap_damage": num(projectile.get("ap_damage")),
                "range": num(projectile.get("effective_range")),
                "ammo": num(lu.get("ammo")),
                "reload_time": num(projectile.get("base_reload_time")),
            })

        unit_abilities = []
        for ability in abilities.get(lu["key"], []):
            title, description = split_title(loc.get(f"unit_abilities_tooltip_text_{ability}"))
            unit_abilities.append({"name": title or ability, "text": description})
        unit_attributes = []
        for attribute in attributes.get(lu.get("attribute_group", ""), []):
            title, description = split_title(loc.get(f"unit_attributes_bullet_text_{attribute}"))
            unit_attributes.append({"name": title or attribute, "text": description})

        strengths = loc.get(f"unit_description_strengths_weaknesses_texts_text_{lu.get('strengths_weaknesses_text', '')}", "")
        recruited_by = sorted({f for g in groups.get(key, ()) for f in factions_by_group.get(g, [])} | exclusive.get(key, set()))
        sources = []
        if buildings.get(key) and recruited_by:
            sources.append("recruit")
        if key in mercenaries:
            sources.append("mercenary")
        if key in garrison:
            sources.append("garrison")
        if key in scripted:
            sources.append("scripted")

        entry = {
            "key": key,
            "land_unit": lu["key"],
            "name": name,
            "culture": culture,
            "campaign": campaign_of(key),
            "category": loc.get(f"unit_category_localised_name_{lu.get('category', '')}", lu.get("category", "")),
            "class": loc.get(f"unit_class_onscreen_{lu.get('class', '')}", lu.get("class", "")),
            "caste": loc.get(f"unit_castes_localised_name_{mu.get('caste', '')}", mu.get("caste", "")),
            "group": loc.get(f"ui_unit_groupings_onscreen_{mu.get('ui_unit_group_land', '')}", ""),
            "card": card,
            "sources": sources,
            "men": num(mu.get("num_men")),
            "mounts": num(lu.get("num_mounts")),
            "cost": num(mu.get("recruitment_cost")),
            "upkeep": num(mu.get("upkeep_cost")),
            "turns": num(mu.get("create_time")),
            "campaign_cap": num(mu.get("campaign_cap")),
            "stats": stats,
            "abilities": unit_abilities,
            "attributes": unit_attributes,
            "short": loc.get(f"unit_description_short_texts_text_{lu.get('short_description_text', '')}", ""),
            "history": loc.get(f"unit_description_historical_texts_text_{lu.get('historical_description_text', '')}", ""),
            "strengths": [s.strip() for s in strengths.split("||") if s.strip()],
            "factions": [{"key": f, "name": loc.get(f"factions_screen_name_{f}", f)} for f in recruited_by],
            "buildings": sorted({building_name(b) for b in buildings.get(key, ())}),
            "links": cultures.links(culture),
        }
        details[key] = entry
        index.append({k: entry[k] for k in ("key", "name", "culture", "campaign", "category", "class", "card", "sources")})

    index.sort(key=lambda e: (e["name"].lower(), e["key"]))
    return index, details


# --- output ----------------------------------------------------------------------------------------------------

def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def main():
    images = "--no-images" not in sys.argv
    if not (EXTRACTED / "fireforged/1/db").is_dir():
        sys.exit("extracted/fireforged is missing: run tools/extract-all.sh")
    if images:
        extract_icons()

    # the site itself, data and images are regenerated below (images only when their source changed)
    for item in SITE.iterdir():
        target = OUT / item.name
        if target.is_dir():
            shutil.rmtree(target)
        if item.is_dir():
            shutil.copytree(item, target)
        else:
            OUT.mkdir(exist_ok=True)
            shutil.copy2(item, target)
    shutil.rmtree(OUT / "data", ignore_errors=True)

    loc = load_loc()
    index, details = build_units(loc, images)
    for key, entry in details.items():
        write_json(OUT / "data/unit" / f"{key}.json", entry)
    write_json(OUT / "data/units.json", index)
    # bar scale per stat: the 98th percentile of the grand campaign's units, so one siege engine doesn't flatten
    # every other bar (values above it fill the bar)
    combined = {
        "weapon": lambda s: s["weapon_damage"] + s["weapon_ap_damage"],
        "missile": lambda s: s.get("missile_damage", 0) + s.get("missile_ap_damage", 0),
        "melee_defence": lambda s: s["melee_defence"] + s["shield_defence"],
        "armour": lambda s: s["armour"] + s["shield_armour"],
    }
    values = {}
    for entry in details.values():
        if entry["campaign"] != "main" or not entry["sources"]:
            continue
        stats = dict(entry["stats"])
        for stat, fn in combined.items():
            stats[stat] = fn(entry["stats"])
        for stat, value in stats.items():
            if value:
                values.setdefault(stat, []).append(value)
    stat_scale = {stat: sorted(v)[int(len(v) * 0.98) - 1] for stat, v in values.items() if v}
    write_json(OUT / "data/meta.json", {
        "built": time.strftime("%Y-%m-%d"),
        "units": len(index),
        "stat_scale": stat_scale,
        "cultures": {cid: {"name": c[0], "links": cultures.links(cid)} for cid, c in cultures.CULTURES.items()},
    })

    # drop cards no unit uses any more
    used = {e["card"] for e in index if e["card"]}
    for path in (OUT / "img/units").glob("*.jpg") if (OUT / "img/units").is_dir() else []:
        if path.stem not in used:
            path.unlink()

    with_card = sum(1 for e in index if e["card"])
    print(f"{len(index)} units ({with_card} with a card) written to {OUT.relative_to(REPO)}/")


if __name__ == "__main__":
    main()
