"""Which late-roman.ru culture page a unit belongs to.

late-roman.ru describes Fireforged's units per culture, two pages each ("Screenshots and description" and
"Gaming information"), with no page per unit. Units are matched by the start of their main unit key, which
Fireforged and the game name after the culture or people (rex_goth_, att_rom_, rex_sarm_, ...). The first match in
PREFIXES wins, so the more specific prefixes come first. Units that match nothing (ships, mercenaries,
Charlemagne and Last Roman units, ...) are "other".
"""

SITE = "https://late-roman.ru/fireforged-empire/units/"

# id -> (name, "screenshots and description" page, "gaming information" page or None)
CULTURES = {
    "roman": ("Roman", "roman-screenshots-description/", "units-roman-culture-gaming-information/"),
    "goth": ("Gothic", "goth-screenshots-description/", "units-goth-culture-gaming-information/"),
    "german": ("Germanic", "german-screenshots-description/", "german-culture-gaming-information/"),
    "eastern": ("Eastern", "eastern-culture-screenshots-description/", "units-eastern-culture-gaming-information/"),
    "sarmatian": ("Sarmatian", "units-sarmatian-culture/", "sarmatian-culture-gaming-information/"),
    "slavic": ("Proto-Slavic", "proto-slavic-culture/", "proto-slavic-culture-gaming-information/"),
    "hun": ("Hunnic", "hun-culture/", None),
    "desert": ("Desert", "units-desert-culture/", "desert-culture-gaming-information/"),
    "celtic": ("Celtic, Pictish, Bagaudae", "celtic-pictish-bagaudae/",
               "celtic-pictish-bagaudae-culture-gaming-information/"),
    "other": ("Other cultures", "other-units-screenshots/", "other-units-gaming-information/"),
}

PREFIXES = [
    # ships and mercenaries first: att_merc_ger_... is a mercenary, not a Germanic line unit
    ("att_shp_", "other"), ("rex_shp_", "other"),
    ("att_merc_", "other"), ("rex_merc", "other"), ("cha_", "other"),
    ("rex_robb", "other"), ("rex_townsfolks", "other"),
    ("rex_rom_", "roman"), ("att_rom_", "roman"), ("bel_rom_", "roman"),
    ("rex_goth_", "goth"), ("rex_vest", "goth"), ("rex_ost", "goth"), ("bel_ost", "goth"),
    ("rex_gepid", "goth"), ("rex_vand", "goth"), ("bel_van", "goth"),
    ("rex_germ_", "german"), ("att_ger_", "german"), ("att_nor_", "german"), ("rex_alem", "german"),
    ("rex_burg", "german"), ("rex_fran", "german"), ("rex_fra_", "german"), ("rex_sax", "german"),
    ("rex_lang", "german"), ("rex_sveb", "german"), ("rex_quad", "german"), ("rex_rug", "german"),
    ("rex_east_", "eastern"), ("att_est_", "eastern"),
    ("rex_sarm_", "sarmatian"), ("rex_alan", "sarmatian"), ("att_alan_", "sarmatian"), ("rex_rox", "sarmatian"),
    ("rex_iaz", "sarmatian"),
    ("rex_slav_", "slavic"), ("att_slav_", "slavic"), ("rex_vend", "slavic"), ("rex_ant", "slavic"),
    ("rex_scl", "slavic"),
    ("rex_hun_", "hun"), ("att_nom_", "hun"), ("att_wh_", "hun"),
    ("rex_des_", "desert"), ("att_des_", "desert"), ("rex_arab_", "desert"), ("rex_axum", "desert"),
    ("rex_celt_", "celtic"), ("att_cel_", "celtic"), ("rex_pict", "celtic"), ("rex_ebd", "celtic"),
    ("rex_vot", "celtic"), ("rex_bag", "celtic"),
]


def culture_of(unit_key):
    for prefix, culture in PREFIXES:
        if unit_key.startswith(prefix):
            return culture
    return "other"


def links(culture):
    name, description, gaming = CULTURES[culture]
    result = [{"title": f"{name} units: screenshots and description", "url": SITE + description}]
    if gaming:
        result.append({"title": f"{name} units: gaming information", "url": SITE + gaming})
    return result
