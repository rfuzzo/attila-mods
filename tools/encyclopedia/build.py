#!/usr/bin/env python3
"""Build the Fireforged Empire encyclopedia (a static site in encyclopedia/) from the game and mod data.

Reads the git-ignored extracted/ folder (tools/extract-all.sh), the unit cards and building pictures in
extracted/icons/ (extracted here on the first run with twpack) and Fireforged's startpos (recruitment areas, through
`twpack esf dump`). Writes encyclopedia/: the site from tools/encyclopedia/site/, the units and building chains as
JSON and their pictures as JPEG. The game links entries as <base>#/unit/<main unit key> and
<base>#/building/<level><culture><subculture><faction>; the site routes on location.hash
(tools/encyclopedia/site/app.js).

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
STARTPOS = "fireforged/1/campaigns/main_attila/startpos.esf"

# Pack roots in extracted/, highest priority first: mod packs override the DLC packs, which override data.pack.
DB_ROOTS = ["fireforged/ballast", "fireforged/1", "game/charlemagne", "game/belisarius", "game/data"]
LOC_ROOTS = ["fireforged/ballast/text", "fireforged/1/text", "game/local_en/text"]
ICON_ROOTS = ["icons/fireforged", "icons/charlemagne", "icons/belisarius", "icons/game"]
# (pack, folder in extracted/, picture folder in the pack); Fireforged ships unit cards but no building pictures
ICON_SOURCES = [
    (GAME_DATA / "data.pack", "icons/game", "ui/units/icons"),
    (FIREFORGED_PACK, "icons/fireforged", "ui/units/icons"),
    (GAME_DATA / "data.pack", "icons/game", "ui/buildings/icons"),
    (GAME_DATA / "charlemagne.pack", "icons/charlemagne", "ui/buildings/icons"),
    (GAME_DATA / "belisarius.pack", "icons/belisarius", "ui/buildings/icons"),
    (GAME_DATA / "data.pack", "icons/game", "ui/campaign ui/technologies"),
]
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


# --- pictures --------------------------------------------------------------------------------------------------

def extract_icons():
    """Unit cards and building pictures of the packs into extracted/icons/ (once; delete the folder to refresh)."""
    for pack, dest, folder in ICON_SOURCES:
        if (EXTRACTED / dest / folder).is_dir():
            continue
        if not pack.is_file():
            print(f"warning: {pack} not found, no {folder} from it", file=sys.stderr)
            continue
        print(f"extracting {folder} from {pack.name}")
        subprocess.run([str(TWPACK), "extract", str(pack), "-o", str(EXTRACTED / dest), f"{folder}/*"],
                       check=True, stdout=subprocess.DEVNULL)


def icon_path(name, folder="ui/units/icons"):
    for root in ICON_ROOTS:
        path = EXTRACTED / root / folder / f"{name}.png"
        if path.is_file():
            return path
    return None


def convert_icon(source, name, kind="units", quality=82):
    """PNG -> encyclopedia/img/<kind>/<name>.jpg (JPEG flattens the transparency onto white, the card colour)."""
    dest = OUT / "img" / kind / f"{name}.jpg"
    if dest.is_file() and dest.stat().st_mtime >= source.stat().st_mtime:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(quality), str(source), "--out", str(dest)],
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


def recruitment_areas(loc):
    """Fireforged's areas of recruitment: region unit resources, which the startpos gives each region (a list per
    region, shortly before its `regions_onscreen_<region>` name key). Units with a region_unit_resource_requirement
    are only recruited in regions that have it. -> {resource: {key, name, provinces: [{name, regions}]}}"""
    regions = {}
    startpos = EXTRACTED / STARTPOS
    if not startpos.is_file():
        print(f"warning: {startpos} not found, no recruitment areas", file=sys.stderr)
        return {}
    dump = subprocess.run([str(TWPACK), "esf", "dump", str(startpos)], check=True, capture_output=True, text=True)
    pending, distance = None, 0
    for line in dump.stdout.splitlines():
        line = line.strip()
        if line.startswith("ascii[] ["):
            pending, distance = re.findall(r'"([^"]*)"', line), 0
            continue
        if pending is not None:
            distance += 1
            match = re.match(r'ascii "regions_onscreen_(\S+)"', line)
            if match:
                for resource in pending:
                    regions.setdefault(resource, []).append(match.group(1))
                pending = None
            elif distance > 8:
                pending = None
    province_of = {row["region"]: row["province"] for row in table("region_to_province_junctions")}
    areas = {}
    for resource, keys in regions.items():
        provinces = {}
        for region in keys:
            province = province_of.get(region, "")
            provinces.setdefault(province, []).append(loc.get(f"regions_onscreen_{region}", region))
        name = loc.get(f"region_unit_resources_string_{resource}") or \
            re.sub(r"(\D)(\d)", r"\1 \2", resource.removeprefix("AOR_").removeprefix("Auxilia_")).replace("_", " ")
        areas[resource] = {
            "key": resource,
            "name": name,
            "provinces": sorted(({"name": loc.get(f"provinces_onscreen_{p}", p), "regions": sorted(r)}
                                 for p, r in provinces.items()), key=lambda e: e["name"]),
        }
    return areas


def build_units(loc, images, factions):
    main_units = table("main_units", "unit")
    land_units = by(table("land_units", "key"), "key")
    melee = by(table("melee_weapons", "key"), "key")
    missile = by(table("missile_weapons", "key"), "key")
    projectiles = by(table("projectiles", "key"), "key")
    armours = by(table("unit_armour_types", "key"), "key")
    shields = by(table("unit_shield_types", "key"), "key")
    mounts = by(table("mounts", "key"), "key")
    entities = by(table("battle_entities", "key"), "key")
    subculture_of = {row["key"]: row.get("subculture", "") for row in factions}
    areas = recruitment_areas(loc)

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
        """The name of a level's first culture variant (the unit page doesn't know the viewer's culture)."""
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
            "subcultures": sorted({subculture_of[f] for f in recruited_by if subculture_of.get(f)}),
            "buildings": sorted(({"level": b, "name": building_name(b)} for b in buildings.get(key, ())),
                                key=lambda e: (e["name"], e["level"])),
            "area": areas.get(mu.get("region_unit_resource_requirement", "")),
            "links": cultures.links(culture),
        }
        details[key] = entry
        index.append({k: entry[k] for k in ("key", "name", "culture", "campaign", "category", "class", "card", "sources")})

    index.sort(key=lambda e: (e["name"].lower(), e["key"]))
    return index, details


# --- buildings -------------------------------------------------------------------------------------------------

CHAIN_CATEGORIES = {"military": "Military", "money": "Economy", "happiness": "Civic"}


def format_effect(text, value):
    """An effect's loc text with its value: %+n signed, %n plain, colour tags dropped."""
    number = num(value)
    signed = f"+{number}" if number > 0 else str(number)
    text = text.replace("%+n", signed).replace("%n", str(abs(number) if "-%n" in text else number))
    return re.sub(r"\[\[/?col(:[a-z_]+)?\]\]", "", text).strip()


def effect_tone(effect, value):
    """good / bad from the effect's icon: effects name a positive and a negative icon, and for effects where more is
    worse (costs, squalor) the 'negative' icon is the one for positive values."""
    icon = effect.get("icon" if num(value) >= 0 else "icon_negative", "")
    return "bad" if "negative" in icon else "good" if "positive" in icon else ""


def build_buildings(loc, images, factions, units):
    levels = by(table("building_levels", "level_name"), "level_name")
    chains = by(table("building_chains", "key"), "key")
    effects = by(table("effects", "effect"), "effect")
    subcultures = {row["subculture"]: row["culture"] for row in table("cultures_subcultures", "subculture")}
    subculture_of = {row["key"]: row.get("subculture", "") for row in factions}

    def expand(culture, subculture, faction):
        """The subcultures an availability or variant row applies to (empty columns match everything)."""
        if faction:
            return {subculture_of[faction]} if subculture_of.get(faction) else set()
        if subculture:
            return {subculture}
        return {sub for sub, cult in subcultures.items() if not culture or cult == culture}

    # who may build a chain: availability rows -> sets -> chains; the campaign column limits rows to one campaign
    chains_of_set = {}
    for row in table("building_chain_availability_sets"):
        chains_of_set.setdefault(row["id"], set()).add(row["building_chain"])
    builders = {}
    for row in table("building_chain_availabilities"):
        for chain in chains_of_set.get(row["set_id"], ()):
            if row["campaign"] and row["campaign"] != {"main": "main_attila", "bel": "bel_attila", "cha": "cha_attila"}[campaign_of(chain)]:
                continue
            builders.setdefault(chain, set()).update(expand(row["culture"], row["sub_culture"], row["faction"]))

    variants = {}
    for row in table("building_culture_variants", ("building", "culture", "subculture", "faction")):
        variants.setdefault(row["building"], []).append(row)

    upgrades, downgrades = {}, {}
    for row in table("building_upgrades_junction"):
        upgrades.setdefault(row["from"], []).append(row["to"])
        downgrades.setdefault(row["to"], []).append(row["from"])
    level_effects = {}
    for row in table("building_effects_junction"):
        level_effects.setdefault(row["building"], []).append(row)
    level_units = {}
    for row in table("building_units_allowed"):
        level_units.setdefault(row["building"], set()).add(row["unit"])
    garrison_groups = {}
    for row in table("building_level_armed_citizenry_junctions"):
        garrison_groups.setdefault(row["building_level"], []).append(row["unit_group"])
    garrison_units = {}
    for row in table("armed_citizenry_units_to_unit_groups_junctions"):
        garrison_units.setdefault(row["unit_group"], []).append(row["unit"])
    techs = {}
    for row in table("building_level_required_technology_junctions"):
        techs.setdefault(row["building_level_key"], []).append(row["technology_key"])
    main_units = by(table("main_units", "unit"), "unit")

    def unit_ref(key):
        unit = units.get(key)
        if unit:
            return {"key": key, "name": unit["name"], "card": unit["card"], "subcultures": unit["subcultures"],
                    "area": unit["area"]["name"] if unit["area"] else ""}
        main = main_units.get(key, {})
        name = loc.get(f"naval_units_onscreen_name_{main.get('naval_unit', '')}") or \
            loc.get(f"land_units_onscreen_name_{main.get('land_unit', '')}") or key
        return {"key": key, "name": name, "card": None, "subcultures": [], "missing": True}

    def picture(icon):
        """The variant's picture (the _large one, 220x155, if the game has it)."""
        for name in (f"{icon}_large", icon):
            source = icon_path(name, "ui/buildings/icons")
            if source:
                if images:
                    convert_icon(source, name, "buildings", 60)
                return name
        return None

    index, details, routes = [], {}, {}
    for chain_key, chain in chains.items():
        chain_levels = sorted((l for l in levels.values() if l["chain"] == chain_key),
                              key=lambda l: (num(l["level"]), l["level_name"]))
        # levels without a culture variant can't be built (Fireforged drops some vanilla branches that way)
        chain_levels = [l for l in chain_levels if variants.get(l["level_name"])] or chain_levels
        if not chain_levels:
            continue
        chain_builders = builders.get(chain_key)
        if not chain_builders:
            # settlement chains are given by the map, not built: their culture variants say whose they are (not the
            # ruin's, level 0, which every culture has)
            built = [level for level in chain_levels if num(level["level"]) > 0] or chain_levels
            rows = [v for level in built for v in variants.get(level["level_name"], [])]
            specific = [v for v in rows if v["culture"] or v["subculture"] or v["faction"]] or rows
            chain_builders = {sub for v in specific for sub in expand(v["culture"], v["subculture"], v["faction"])}
        if campaign_of(chain_key) == "main":
            chain_builders = {sub for sub in chain_builders if not sub.startswith(("bel_", "cha_"))}
        routes[chain_key] = chain_key
        unit_refs = {}
        level_entries = []
        for level in chain_levels:
            key = level["level_name"]
            level_variants = []
            for v in variants.get(key, []):
                vid = key + v["culture"] + v["subculture"] + v["faction"]
                routes[vid] = chain_key
                level_variants.append({
                    "id": vid,
                    "subcultures": sorted(expand(v["culture"], v["subculture"], v["faction"])),
                    "faction": v["faction"],
                    "name": loc.get(f"building_culture_variants_name_{vid}") or key,
                    "picture": picture(v["icon"]) if v.get("icon") else None,
                    "short": loc.get(f"building_short_description_texts_short_description_{v.get('short_description', '')}", ""),
                    "flavour": loc.get(f"building_flavour_texts_flavour_{v.get('flavour', '')}", ""),
                })
            routes[key] = chain_key
            level_effects_list = []
            for row in level_effects.get(key, []):
                text = loc.get(f"effects_description_{row['effect']}")
                if not text:
                    continue
                scope = loc.get(f"campaign_effect_scopes_localised_text_{row['effect_scope']}", "").strip()
                level_effects_list.append({
                    "text": format_effect(text, row["value"]) + (" " + scope if scope else ""),
                    "tone": effect_tone(effects.get(row["effect"], {}), row["value"]),
                })
            recruits = sorted(level_units.get(key, ()))
            garrison = sorted({u for g in garrison_groups.get(key, []) for u in garrison_units.get(g, [])})
            for unit in recruits + garrison:
                unit_refs.setdefault(unit, unit_ref(unit))
            level_entries.append({
                "key": key,
                "tier": num(level["level"]) + 1,
                "cost": num(level["create_cost"]),
                "turns": num(level["create_time"]),
                "upkeep": num(level["upkeep_cost"]),
                "capital_only": level["only_in_capital"] == "true",
                "religion": loc.get(f"religions_onscreen_{level['religion_requirement']}", level["religion_requirement"]),
                "resource": loc.get(f"resources_onscreen_text_{level['resource_requirement']}", level["resource_requirement"]),
                "techs": sorted(({"key": t, "name": loc.get(f"technologies_onscreen_name_{t}", t)} for t in set(techs.get(key, []))),
                                key=lambda e: (e["name"], e["key"])),
                "upgrades": [u for u in upgrades.get(key, []) if variants.get(u)],
                "from": [u for u in downgrades.get(key, []) if variants.get(u)],
                "variants": level_variants,
                "effects": level_effects_list,
                "units": recruits,
                "garrison": garrison,
            })

        name = loc.get(f"building_chains_encyclopedia_name_{chain_key}") or \
            loc.get(f"building_chains_chain_tooltip_{chain_key}") or chain_key
        entry = {
            "key": chain_key,
            "name": name,
            "description": loc.get(f"building_chains_encyclopedia_description_{chain_key}", "").replace("Placeholder description", ""),
            "category": CHAIN_CATEGORIES.get(chain["chain_category"], "Other"),
            "campaign": campaign_of(chain_key),
            "builders": sorted(chain_builders),
            "levels": level_entries,
            "units": unit_refs,
        }
        details[chain_key] = entry
        # the list shows each chain with the picture of its first tier, per subculture where they differ
        looks = {}
        for v in level_entries[0]["variants"]:
            for sub in v["subcultures"]:
                looks.setdefault(sub, [v["name"], v["picture"]])
        first = level_entries[0]["variants"][0] if level_entries[0]["variants"] else {"name": name, "picture": None}
        if all(l["key"].endswith("_ruin") for l in level_entries):
            continue  # a culture's razed settlement: reachable from the game's links, not worth a place in the list
        index.append({
            "key": chain_key,
            "name": name,
            "category": entry["category"],
            "campaign": entry["campaign"],
            "builders": entry["builders"],
            "tiers": len({l["tier"] for l in level_entries}),
            "look": [first["name"], first["picture"]],
            "looks": {sub: look for sub, look in looks.items() if look != [first["name"], first["picture"]]},
        })

    index.sort(key=lambda e: (e["name"].lower(), e["key"]))
    names = {sub: loc.get(f"cultures_subcultures_name_{sub}", sub) for sub in subcultures}
    return index, details, routes, names


def name_buildings(units, chains, routes):
    """A unit's buildings as its recruiters see them: only levels of chains one of their subcultures can build, named
    after that subculture's variant. (building_units_allowed lists whole culture groups' units on shared levels.)"""
    for unit in units.values():
        subs = set(unit["subcultures"])
        result = {}
        for building in unit["buildings"]:
            chain = chains.get(routes.get(building["level"], ""))
            if not chain:
                continue
            if subs and not subs & set(chain["builders"]):
                continue
            level = next(l for l in chain["levels"] if l["key"] == building["level"])
            names = [v["name"] for v in level["variants"] if not subs or subs & set(v["subcultures"])] or \
                [v["name"] for v in level["variants"]] or [chain["name"]]
            result[building["level"]] = {"level": building["level"], "chain": chain["key"], "name": names[0]}
        unit["buildings"] = sorted(result.values(), key=lambda e: (e["name"], e["level"]))


# --- technologies ----------------------------------------------------------------------------------------------

TECH_KINDS = {"rom_roman_civ_top": "Civil", "rom_roman_mil_top": "Military"}
CAMPAIGNS = {"": "main", "main_attila": "main", "bel_attila": "bel", "cha_attila": "cha"}


def build_techs(loc, images, factions, units, chains, routes):
    """Technology trees: node sets (one per culture, subculture or faction and campaign, civil or military) of nodes
    placed by tier (column) and indent (row), linked parent -> child. A node with a faction_key is that faction's
    replacement for the generic node in the same place (Fireforged gives the Roman empires, Goths, Slavs, Picts...
    their own technologies that way)."""
    techs = by(table("technologies", "key"), "key")
    nodes = table("technology_nodes", "key")
    subcultures = {row["subculture"]: row["culture"] for row in table("cultures_subcultures", "subculture")}
    subculture_of = {row["key"]: row.get("subculture", "") for row in factions}
    effects = by(table("effects", "effect"), "effect")
    tech_effects = {}
    for row in table("technology_effects_junction"):
        tech_effects.setdefault(row["technology"], []).append(row)
    upgrades = {}
    for row in table("technology_unit_upgrades"):
        upgrades.setdefault(row["technology"], []).append(row)
    unlocks = {}
    for row in table("building_level_required_technology_junctions"):
        unlocks.setdefault(row["technology_key"], []).append(row["building_level_key"])
    parents = {}
    for row in table("technology_node_links"):
        parents.setdefault(row["child_key"], []).append(row["parent_key"])

    def unit_name(key):
        unit = units.get(key)
        return unit["name"] if unit else key

    def picture(icon):
        source = icon_path(icon, "ui/campaign ui/technologies")
        if not source:
            return None
        if images:
            dest = OUT / "img/techs" / f"{icon}.png"
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, dest)  # 53x53 with transparency, small as it is
        return icon

    index, details, tech_routes = [], {}, {}
    faction_sets = {row["key"] for row in table("technology_node_sets", "key") if row["faction_key"]}
    for node_set in table("technology_node_sets", "key"):
        set_key = node_set["key"]
        set_nodes = sorted((n for n in nodes if n["technology_node_set"] == set_key and n["technology_key"] in techs),
                           key=lambda n: (num(n["tier"]), num(n["indent"]), n["key"]))
        if not set_nodes:
            continue
        faction, subculture, culture = node_set["faction_key"], node_set["subculture"], node_set["culture"]
        if faction:
            who, subs = loc.get(f"factions_screen_name_{faction}", faction), {subculture_of.get(faction, "")}
        elif subculture:
            who, subs = loc.get(f"cultures_subcultures_name_{subculture}", subculture), {subculture}
        elif culture:
            who, subs = loc.get(f"cultures_name_{culture}", culture), {s for s, c in subcultures.items() if c == culture}
        else:
            who, subs = "Other factions", set()
        kind = TECH_KINDS.get(node_set["technology_category"], "")
        campaign = CAMPAIGNS.get(node_set["campaign_key"], "main")
        if set_key.startswith(("bel_", "cha_")):
            campaign = set_key[:3]

        def building_ref(level):
            chain = chains.get(routes.get(level, ""))
            if not chain:
                return None
            entry = next((l for l in chain["levels"] if l["key"] == level), None)
            if not entry:
                return None
            names = [v["name"] for v in entry["variants"] if subs & set(v["subcultures"])] or \
                [v["name"] for v in entry["variants"]] or [chain["name"]]
            return {"level": level, "name": names[0]}

        tech_routes[set_key] = set_key
        node_entries = []
        for node in set_nodes:
            tech = techs[node["technology_key"]]
            key = tech["key"]
            tech_routes.setdefault(node["key"], set_key)
            # a technology key in several sets: prefer the grand campaign's culture sets
            if key not in tech_routes or (campaign == "main" and not faction and tech_routes[key] in faction_sets):
                tech_routes[key] = set_key
            effect_list = []
            for row in tech_effects.get(key, []):
                text = loc.get(f"effects_description_{row['effect']}")
                if not text:
                    continue
                scope = loc.get(f"campaign_effect_scopes_localised_text_{row['effect_scope']}", "").strip()
                effect_list.append({"text": format_effect(text, row["value"]) + (" " + scope if scope else ""),
                                    "tone": effect_tone(effects.get(row["effect"], {}), row["value"])})
            node_entries.append({
                "key": node["key"],
                "tech": key,
                "faction": node["faction_key"],
                "name": loc.get(f"technologies_onscreen_name_{key}", key),
                "icon": picture(tech["icon_name"]),
                "tier": num(node["tier"]),
                "row": num(node["indent"]),
                "points": num(node["research_points_required"]),
                "short": loc.get(f"technologies_short_description_{key}", ""),
                "long": loc.get(f"technologies_long_description_{key}", ""),
                "effects": effect_list,
                "upgrades": [{"unit": u["unit"], "name": unit_name(u["unit"]), "to": u["target_unit"],
                              "to_name": unit_name(u["target_unit"]), "cost": num(u["cost"])}
                             for u in sorted(upgrades.get(key, []), key=lambda u: (unit_name(u["unit"]), u["unit"]))],
                "buildings": sorted(filter(None, (building_ref(l) for l in set(unlocks.get(key, [])))),
                                    key=lambda e: (e["name"], e["level"])),
                "parents": sorted(parents.get(node["key"], [])),
            })
        name = f"{who}: {kind.lower()} technologies" if kind else f"{who} technologies"
        own_factions = sorted({n["faction"] for n in node_entries if n["faction"]})
        details[set_key] = {"key": set_key, "name": name, "who": who, "kind": kind, "campaign": campaign,
                            "faction": faction, "nodes": node_entries,
                            "factions": [{"key": f, "name": loc.get(f"factions_screen_name_{f}", f)} for f in own_factions]}
        index.append({"key": set_key, "name": name, "who": who, "kind": kind, "campaign": campaign,
                      "faction": bool(faction), "count": len(node_entries), "icon": node_entries[0]["icon"]})

    index.sort(key=lambda e: (e["campaign"] != "main", e["faction"], e["who"].lower(), e["kind"]))
    return index, details, tech_routes


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
    factions = table("factions", "key")
    index, details = build_units(loc, images, factions)
    building_index, chains, routes, subculture_names = build_buildings(loc, images, factions, details)
    name_buildings(details, chains, routes)
    for key, entry in chains.items():
        write_json(OUT / "data/building" / f"{key}.json", entry)
    write_json(OUT / "data/buildings.json", building_index)
    tech_index, tech_sets, tech_routes = build_techs(loc, images, factions, details, chains, routes)
    for key, entry in tech_sets.items():
        write_json(OUT / "data/tech" / f"{key}.json", entry)
    write_json(OUT / "data/techs.json", tech_index)
    write_json(OUT / "data/tech_routes.json", tech_routes)
    for key, entry in details.items():
        write_json(OUT / "data/unit" / f"{key}.json", entry)
    write_json(OUT / "data/units.json", index)
    write_json(OUT / "data/building_routes.json", routes)
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
        "buildings": len(building_index),
        "techs": len(tech_index),
        "aor_map": cultures.AOR_MAP,
        "stat_scale": stat_scale,
        # the grand campaign's subcultures (of its att_ factions), the list's culture chips
        "subcultures": {sub: subculture_names[sub] for sub in sorted(
            {row.get("subculture") for row in factions if row["key"].startswith("att_fact_") and row.get("subculture")
             and not PLACEHOLDER_FACTION.search(row["key"])}) if sub in subculture_names},
        "cultures": {cid: {"name": c[0], "links": cultures.links(cid)} for cid, c in cultures.CULTURES.items()},
    })

    # drop pictures nothing uses any more
    used = {"units": {e["card"] for e in index if e["card"]},
            "buildings": {v["picture"] for c in chains.values() for l in c["levels"] for v in l["variants"] if v["picture"]},
            "techs": {n["icon"] for t in tech_sets.values() for n in t["nodes"] if n["icon"]}}
    for kind, names in used.items():
        for path in (OUT / "img" / kind).glob("*.*") if (OUT / "img" / kind).is_dir() else []:
            if path.stem not in names:
                path.unlink()

    with_card = sum(1 for e in index if e["card"])
    print(f"{len(index)} units ({with_card} with a card), {len(building_index)} building chains and "
          f"{len(tech_index)} technology trees written to {OUT.relative_to(REPO)}/")


if __name__ == "__main__":
    main()
