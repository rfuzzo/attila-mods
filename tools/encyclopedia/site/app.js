// Fireforged Empire encyclopedia. The game opens <base>#/unit/<main unit key> (and #/building/..., #/tech/...,
// #/skill/..., #/character/..., #/tradition/..., #/manual/...), so everything routes on location.hash.
// Data: data/units.json (the list), data/unit/<key>.json (one unit), data/buildings.json (the chains),
// data/building/<chain>.json (one chain with its levels), data/building_routes.json (level / variant / chain key ->
// chain), data/techs.json (the technology trees), data/tech/<set>.json (one tree), data/tech_routes.json (node /
// technology / set key -> tree), data/meta.json (cultures, subcultures, stat maxima).
(function () {
  "use strict";

  var view = document.getElementById("view");
  var cache = {};
  var state = { campaign: "main", category: "", query: "", unused: false, buildingCategory: "", sub: "", techView: {} };

  var SOURCES = {
    recruit: "Recruitable",
    mercenary: "Mercenary",
    garrison: "Garrison",
    scripted: "Spawned by campaign events"
  };

  // units with no way to get them in the data: vanilla units Fireforged no longer uses
  function used(u) { return u.sources.length > 0; }

  function load(path) {
    if (!cache[path]) {
      cache[path] = fetch(path).then(function (response) {
        if (!response.ok) throw new Error(response.status === 404 ? "not found" : "HTTP " + response.status);
        return response.json();
      });
    }
    return cache[path];
  }

  function escapeHtml(text) {
    return String(text == null ? "" : text).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function cardImage(card, name, eager) {
    if (!card) return '<span class="card-img none" aria-hidden="true">?</span>';
    return '<img class="card-img" src="img/units/' + encodeURIComponent(card) + '.jpg" alt="' + escapeHtml(name) +
      '" width="64" height="152"' + (eager ? "" : ' loading="lazy"') + ">";
  }

  function render(html) {
    view.innerHTML = html;
    window.scrollTo(0, 0);
  }

  function setTitle(text) {
    document.title = (text ? text + " · " : "") + "Fireforged Empire Encyclopedia";
  }

  function markNav(route) {
    var links = document.querySelectorAll(".top-nav a");
    var section = route.indexOf("unit") === 0 ? "#/units" : route.indexOf("building") === 0 ? "#/buildings" :
      route.indexOf("tech") === 0 ? "#/techs" : "";
    for (var i = 0; i < links.length; i++) {
      links[i].classList.toggle("active", links[i].getAttribute("href") === section);
    }
  }

  // --- home ---------------------------------------------------------------------------------------------------

  function buildingPicture(name, alt, cls) {
    if (!name) return '<span class="' + (cls || "bld-pic") + ' none" aria-hidden="true"></span>';
    return '<img class="' + (cls || "bld-pic") + '" src="img/buildings/' + encodeURIComponent(name) + '.jpg" alt="' +
      escapeHtml(alt || "") + '" loading="lazy">';
  }

  function home(meta, units) {
    setTitle("");
    var byCulture = {};
    units.forEach(function (u) {
      if (u.campaign !== "main" || !used(u)) return;
      (byCulture[u.culture] = byCulture[u.culture] || []).push(u);
    });
    var tiles = Object.keys(meta.cultures).map(function (id) {
      var list = byCulture[id] || [];
      var faces = list.filter(function (u) { return u.card; }).slice(0, 4).map(function (u) {
        return '<img src="img/units/' + encodeURIComponent(u.card) + '.jpg" alt="" loading="lazy">';
      }).join("");
      return '<a class="culture" href="#/units/' + id + '"><span class="faces">' + faces + '</span><span class="meta">' +
        '<h3>' + escapeHtml(meta.cultures[id].name) + '</h3><span class="count">' + list.length + ' units</span></span></a>';
    }).join("");
    render(
      '<section class="hero"><h1>Fireforged Empire Encyclopedia</h1>' +
      '<p>Every unit of the Fireforged Empire mod for Total War: ATTILA, with its stats, abilities, recruitment and ' +
      'the mod\'s own historical descriptions, its buildings with their effects and recruits, and its technology ' +
      'trees. The unit, building and technology links in the game lead here when the ' +
      '<code>fireforged_encyclopedia</code> TWASE mod is enabled. For screenshots and the authors\' notes on each ' +
      'culture, follow the links to the <a href="https://late-roman.ru/fireforged-empire/units/" target="_blank" ' +
      'rel="noopener">mod website</a>.</p></section>' +
      '<h2>Units by culture</h2><div class="culture-grid">' + tiles + '</div>' +
      '<h2 class="spaced">Buildings by culture</h2><div class="chips">' +
      Object.keys(meta.subcultures).map(function (sub) {
        return '<a class="chip" href="#/buildings/' + sub + '">' + escapeHtml(meta.subcultures[sub]) + "</a>";
      }).join("") + "</div>" +
      '<h2 class="spaced">Technologies</h2><p><a href="#/techs">The technology trees of every culture and faction</a></p>'
    );
  }

  // --- unit list ----------------------------------------------------------------------------------------------

  function unitList(meta, units, culture) {
    var title = culture && meta.cultures[culture] ? meta.cultures[culture].name + " units" : "All units";
    setTitle(title);
    var categories = {};
    units.forEach(function (u) { if (u.category) categories[u.category] = true; });

    var chips = '<a class="chip' + (culture ? "" : " active") + '" href="#/units">All</a>' +
      Object.keys(meta.cultures).map(function (id) {
        return '<a class="chip' + (id === culture ? " active" : "") + '" href="#/units/' + id + '">' +
          escapeHtml(meta.cultures[id].name) + "</a>";
      }).join("");

    var links = culture && meta.cultures[culture] ? meta.cultures[culture].links.map(function (l) {
      return '<a href="' + escapeHtml(l.url) + '" target="_blank" rel="noopener">' + escapeHtml(l.title) + " ↗</a>";
    }).join(" · ") : "";

    render(
      '<div class="list-head"><h1>' + escapeHtml(title) + '</h1><span class="count" id="count"></span></div>' +
      (links ? '<p class="links-inline">' + links + "</p>" : "") +
      '<div class="chips">' + chips + "</div>" +
      '<div class="filters">' +
      '<select id="f-campaign" aria-label="Campaign"><option value="main">Grand campaign</option>' +
      '<option value="all">All campaigns</option><option value="bel">The Last Roman</option>' +
      '<option value="cha">Age of Charlemagne</option></select>' +
      '<select id="f-category" aria-label="Category"><option value="">All categories</option>' +
      Object.keys(categories).sort().map(function (c) {
        return '<option value="' + escapeHtml(c) + '">' + escapeHtml(c) + "</option>";
      }).join("") + "</select>" +
      '<label class="check"><input type="checkbox" id="f-unused"> Units without recruitment</label></div>' +
      '<div class="unit-grid" id="grid"></div>'
    );

    var campaignSelect = document.getElementById("f-campaign");
    var categorySelect = document.getElementById("f-category");
    var unusedBox = document.getElementById("f-unused");
    campaignSelect.value = state.campaign;
    categorySelect.value = state.category;
    unusedBox.checked = state.unused;

    function update() {
      state.campaign = campaignSelect.value;
      state.category = categorySelect.value;
      state.unused = unusedBox.checked;
      var query = state.query.toLowerCase();
      var shown = units.filter(function (u) {
        return (!culture || u.culture === culture) &&
          (state.campaign === "all" || u.campaign === state.campaign) &&
          (!state.category || u.category === state.category) &&
          (state.unused || used(u)) &&
          (!query || u.name.toLowerCase().indexOf(query) >= 0 || u.key.indexOf(query) >= 0);
      });
      document.getElementById("count").textContent = shown.length + " units" + (state.query ? ' matching "' + state.query + '"' : "");
      document.getElementById("grid").innerHTML = shown.length ? shown.map(function (u) {
        return '<a class="unit-tile" href="#/unit/' + encodeURIComponent(u.key) + '">' + cardImage(u.card, u.name) +
          '<span class="name">' + escapeHtml(u.name) + '</span><span class="sub">' + escapeHtml(u.class) + "</span></a>";
      }).join("") : '<p class="empty">No units match.</p>';
    }
    campaignSelect.addEventListener("change", update);
    categorySelect.addEventListener("change", update);
    unusedBox.addEventListener("change", update);
    update();
  }

  // --- one unit -----------------------------------------------------------------------------------------------

  var STAT_ROWS = [
    ["melee_attack", "Melee attack"],
    ["weapon", "Weapon strength", function (s) { return s.weapon_damage + s.weapon_ap_damage; },
      function (s) { return s.weapon_damage + " base + " + s.weapon_ap_damage + " armour-piercing" +
        (s.bonus_v_infantry ? ", +" + s.bonus_v_infantry + " vs infantry" : "") +
        (s.bonus_v_cavalry ? ", +" + s.bonus_v_cavalry + " vs cavalry" : ""); }],
    ["charge_bonus", "Charge bonus"],
    ["melee_defence", "Melee defence", function (s) { return s.melee_defence + s.shield_defence; },
      function (s) { return s.shield_defence ? s.melee_defence + " + " + s.shield_defence + " from the shield" : ""; }],
    ["armour", "Armour", function (s) { return s.armour + s.shield_armour; },
      function (s) { return s.shield_armour ? s.armour + " body + " + s.shield_armour + " shield (front)" : ""; }],
    ["missile_block", "Missile block", null, function () { return "chance to block missiles from the front, in %"; }],
    ["morale", "Morale"],
    ["hit_points", "Hit points", null, function (s) { return s.mount_hit_points ? "rider; the mount has " + s.mount_hit_points : ""; }],
    ["speed", "Speed"],
    ["missile", "Missile strength", function (s) { return s.missile_damage + s.missile_ap_damage; },
      function (s) { return s.missile_damage + " base + " + s.missile_ap_damage + " armour-piercing"; }],
    ["range", "Range"],
    ["ammo", "Ammunition"],
    ["accuracy", "Accuracy"]
  ];

  function statRows(stats, max) {
    return STAT_ROWS.map(function (row) {
      var id = row[0];
      var value = row[2] ? row[2](stats) : stats[id];
      if (id === "missile" && stats.missile_damage === undefined) return "";
      if ((id === "range" || id === "ammo" || id === "accuracy") && stats.range === undefined) return "";
      if (id === "missile_block" && !value) return "";
      if (value === undefined || value === null) return "";
      var top = max[id] || value || 1;
      var width = Math.max(2, Math.min(100, Math.round(100 * value / (top || 1))));
      var note = row[3] ? row[3](stats) : "";
      return '<div class="stat"><span class="label">' + row[1] + '</span><span class="bar"><span style="width:' + width +
        '%"></span></span><span class="value">' + value + "</span>" +
        (note ? '<span class="note">' + escapeHtml(note) + "</span>" : "") + "</div>";
    }).join("");
  }

  function traits(list) {
    return '<div class="traits">' + list.map(function (t) {
      return '<div class="trait"><h3>' + escapeHtml(t.name) + "</h3>" + (t.text ? "<p>" + escapeHtml(t.text) + "</p>" : "") + "</div>";
    }).join("") + "</div>";
  }

  function unitPage(meta, key) {
    return load("data/unit/" + encodeURIComponent(key) + ".json").then(function (u) {
      setTitle(u.name);
      var culture = meta.cultures[u.culture] || { name: u.culture };
      var facts = [
        ["Soldiers", u.men + (u.mounts ? " (" + u.mounts + " mounts)" : "")],
        ["Recruitment cost", u.cost],
        ["Upkeep", u.upkeep],
        ["Recruitment time", u.turns + (u.turns === 1 ? " turn" : " turns")]
      ];
      if (u.campaign_cap > 0) facts.push(["Campaign limit", u.campaign_cap]);
      facts.push(["Available as", u.sources.length ? u.sources.map(function (s) { return SOURCES[s] || s; }).join(", ")
        : "not recruitable in Fireforged"]);
      var factions = u.factions.map(function (f) { return "<li>" + escapeHtml(f.name) + "</li>"; }).join("");
      var buildings = u.buildings.map(function (b) {
        return '<li><a href="#/building/' + encodeURIComponent(b.level) + '">' + escapeHtml(b.name) + "</a></li>";
      }).join("");
      var area = u.area ? '<section class="section"><h2>Area of recruitment</h2>' +
        "<p>Recruitable only in regions of the area <strong>" + escapeHtml(u.area.name) + "</strong>:</p>" +
        '<ul class="plain-list">' + u.area.provinces.map(function (p) {
          return "<li><strong>" + escapeHtml(p.name) + "</strong>: " + p.regions.map(escapeHtml).join(", ") + "</li>";
        }).join("") + "</ul>" +
        '<p class="links-inline"><a href="' + escapeHtml(meta.aor_map) + '" target="_blank" rel="noopener">Map of the ' +
        "areas of recruitment ↗</a> (late-roman.ru)</p></section>" : "";
      var links = u.links.map(function (l) {
        return '<a href="' + escapeHtml(l.url) + '" target="_blank" rel="noopener">' + escapeHtml(l.title) + " ↗</a>";
      }).join("");

      render(
        '<article class="unit"><aside class="unit-side">' + cardImage(u.card, u.name, true) +
        '<dl class="facts">' + facts.map(function (f) { return "<dt>" + f[0] + "</dt><dd>" + escapeHtml(f[1]) + "</dd>"; }).join("") + "</dl>" +
        "</aside><div class=\"unit-main\">" +
        '<div class="crumbs"><a href="#/units/' + escapeHtml(u.culture) + '">' + escapeHtml(culture.name) + " units</a></div>" +
        "<h1>" + escapeHtml(u.name) + "</h1>" +
        '<p class="subtitle">' + [u.class, u.category, u.caste].filter(function (v, i, all) { return v && all.indexOf(v) === i; }).map(escapeHtml).join(" · ") + "</p>" +
        (u.short ? '<p class="section short">' + escapeHtml(u.short) + "</p>" : "") +
        '<section class="section"><h2>Statistics</h2><div class="stats">' + statRows(u.stats, meta.stat_scale) + "</div></section>" +
        (u.strengths.length ? '<section class="section"><h2>Strengths and weaknesses</h2><ul class="strengths">' +
          u.strengths.map(function (s) { return "<li>" + escapeHtml(s) + "</li>"; }).join("") + "</ul></section>" : "") +
        (u.abilities.length ? '<section class="section"><h2>Abilities</h2>' + traits(u.abilities) + "</section>" : "") +
        (u.attributes.length ? '<section class="section"><h2>Attributes</h2>' + traits(u.attributes) + "</section>" : "") +
        (u.history ? '<section class="section"><h2>History</h2><p class="history">' + escapeHtml(u.history) + "</p></section>" : "") +
        (factions ? '<section class="section"><h2>Recruited by</h2><ul class="plain-list">' + factions + "</ul></section>" : "") +
        area +
        (buildings ? '<section class="section"><h2>Recruited in</h2><ul class="plain-list">' + buildings + "</ul></section>" : "") +
        '<section class="section links"><h2>On the mod website</h2>' + links + "</section>" +
        '<p class="keys">' + escapeHtml(u.key) + (u.land_unit !== u.key ? " · land unit " + escapeHtml(u.land_unit) : "") + "</p>" +
        "</div></article>"
      );
    });
  }

  // --- building list ------------------------------------------------------------------------------------------

  function subName(meta, sub) { return meta.subcultures[sub] || sub.replace(/^[a-z]+_sub_cult_/, "").replace(/_/g, " "); }

  function buildingList(meta, chains, sub) {
    if (sub && !meta.subcultures[sub]) sub = "";
    if (sub) state.sub = sub;
    var title = sub ? subName(meta, sub) + " buildings" : "All buildings";
    setTitle(title);
    var chips = '<a class="chip' + (sub ? "" : " active") + '" href="#/buildings">All</a>' +
      Object.keys(meta.subcultures).map(function (id) {
        return '<a class="chip' + (id === sub ? " active" : "") + '" href="#/buildings/' + id + '">' +
          escapeHtml(meta.subcultures[id]) + "</a>";
      }).join("");
    var categories = {};
    chains.forEach(function (c) { categories[c.category] = true; });

    render(
      '<div class="list-head"><h1>' + escapeHtml(title) + '</h1><span class="count" id="count"></span></div>' +
      '<div class="chips">' + chips + "</div>" +
      '<div class="filters">' +
      '<select id="f-campaign" aria-label="Campaign"><option value="main">Grand campaign</option>' +
      '<option value="all">All campaigns</option><option value="bel">The Last Roman</option>' +
      '<option value="cha">Age of Charlemagne</option></select>' +
      '<select id="f-category" aria-label="Category"><option value="">All categories</option>' +
      Object.keys(categories).sort().map(function (c) {
        return '<option value="' + escapeHtml(c) + '">' + escapeHtml(c) + "</option>";
      }).join("") + "</select></div>" +
      '<div class="building-grid" id="grid"></div>'
    );

    var campaignSelect = document.getElementById("f-campaign");
    var categorySelect = document.getElementById("f-category");
    campaignSelect.value = state.campaign;
    categorySelect.value = state.buildingCategory;

    function update() {
      state.campaign = campaignSelect.value;
      state.buildingCategory = categorySelect.value;
      var query = state.query.toLowerCase();
      var shown = chains.filter(function (c) {
        var look = (sub && c.looks[sub]) || c.look;
        return (!sub || c.builders.indexOf(sub) >= 0) &&
          (state.campaign === "all" || c.campaign === state.campaign) &&
          (!state.buildingCategory || c.category === state.buildingCategory) &&
          (!query || c.name.toLowerCase().indexOf(query) >= 0 || look[0].toLowerCase().indexOf(query) >= 0 ||
            c.key.indexOf(query) >= 0);
      });
      document.getElementById("count").textContent = shown.length + " building chains" +
        (state.query ? ' matching "' + state.query + '"' : "");
      document.getElementById("grid").innerHTML = shown.length ? shown.map(function (c) {
        var look = (sub && c.looks[sub]) || c.look;
        return '<a class="building-tile" href="#/building/' + encodeURIComponent(c.key) + '">' +
          buildingPicture(look[1], look[0]) + '<span class="name">' + escapeHtml(c.name) + "</span>" +
          '<span class="sub">' + escapeHtml(c.category) + " · " + c.tiers + (c.tiers === 1 ? " tier" : " tiers") +
          (look[0] !== c.name ? " · " + escapeHtml(look[0]) : "") + "</span></a>";
      }).join("") : '<p class="empty">No buildings match.</p>';
    }
    campaignSelect.addEventListener("change", update);
    categorySelect.addEventListener("change", update);
    update();
  }

  // --- one building chain -------------------------------------------------------------------------------------

  // the variant a subculture sees: one made for it, else the first
  function variantFor(level, sub) {
    var own = level.variants.filter(function (v) { return v.subcultures.indexOf(sub) >= 0; });
    var general = own.filter(function (v) { return !v.faction; });
    return general[0] || own[0] || level.variants[0] || { name: level.key, picture: null, short: "", flavour: "" };
  }

  // the game's key is <level><culture><subculture><faction>; our own links use the level or chain key
  function resolveBuilding(routes, id) {
    if (routes[id]) return { chain: routes[id], id: id };
    var best = "";
    Object.keys(routes).forEach(function (key) {
      if (key.length > best.length && id.indexOf(key) === 0) best = key;
    });
    return best ? { chain: routes[best], id: best } : null;
  }

  function unitTiles(chain, keys, sub) {
    var units = keys.map(function (k) { return chain.units[k]; }).filter(function (u) {
      return u && (!sub || !u.subcultures.length || u.subcultures.indexOf(sub) >= 0);
    });
    if (!units.length) return "";
    return '<div class="unit-grid">' + units.map(function (u) {
      var inner = cardImage(u.card, u.name) + '<span class="name">' + escapeHtml(u.name) + "</span>" +
        (u.area ? '<span class="sub">only in ' + escapeHtml(u.area) + "</span>" : "");
      return u.missing ? '<span class="unit-tile">' + inner + "</span>" :
        '<a class="unit-tile" href="#/unit/' + encodeURIComponent(u.key) + '">' + inner + "</a>";
    }).join("") + "</div>";
  }

  function buildingPage(meta, routes, id) {
    var target = resolveBuilding(routes, id);
    if (!target) return Promise.reject(new Error("not found"));
    return load("data/building/" + encodeURIComponent(target.chain) + ".json").then(function (chain) {
      var level = null, variant = null;
      chain.levels.forEach(function (l) {
        if (l.key === target.id) level = l;
        l.variants.forEach(function (v) { if (v.id === target.id) { level = l; variant = v; } });
      });
      level = level || chain.levels.filter(function (l) { return l.variants.length; })[0] || chain.levels[0];

      // whose view: the variant the game asked for, else the subculture picked before, else the first builder
      var subs = chain.builders.filter(function (s) { return meta.subcultures[s]; });
      if (!subs.length) subs = chain.builders.slice();
      var sub = variant && variant.subcultures.filter(function (s) { return subs.indexOf(s) >= 0; })[0];
      if (!sub) sub = subs.indexOf(state.sub) >= 0 ? state.sub : subs[0] || "";
      if (variant && subs.indexOf(sub) < 0) subs.push(sub);
      state.sub = sub;
      var shown = variant || variantFor(level, sub);

      function levelLink(key) {
        var l = chain.levels.filter(function (x) { return x.key === key; })[0];
        return l ? '<a href="#/building/' + encodeURIComponent(key) + '">' + escapeHtml(variantFor(l, sub).name) + "</a>" : escapeHtml(key);
      }

      var tiers = {};
      chain.levels.forEach(function (l) { (tiers[l.tier] = tiers[l.tier] || []).push(l); });
      var tree = Object.keys(tiers).sort(function (a, b) { return a - b; }).map(function (t) {
        return '<div class="tier"><span class="tier-label">Tier ' + t + '</span><div class="tier-levels">' +
          tiers[t].map(function (l) {
            var v = variantFor(l, sub);
            return '<a class="level-card' + (l === level ? " active" : "") + '" href="#/building/' + encodeURIComponent(l.key) + '">' +
              buildingPicture(v.picture, v.name, "level-pic") + '<span class="name">' + escapeHtml(v.name) + "</span></a>";
          }).join("") + "</div></div>";
      }).join("");

      var facts = [["Cost", level.cost], ["Construction time", level.turns + (level.turns === 1 ? " turn" : " turns")]];
      if (level.upkeep) facts.push(["Upkeep", level.upkeep]);
      if (level.capital_only) facts.push(["Only in", "the provincial capital"]);
      if (level.religion) facts.push(["Religion", level.religion]);
      if (level.resource) facts.push(["Resource", level.resource]);

      var selector = subs.length > 1 ? '<label class="view-as">Culture <select id="f-sub">' + subs.map(function (s) {
        return '<option value="' + escapeHtml(s) + '"' + (s === sub ? " selected" : "") + ">" + escapeHtml(subName(meta, s)) + "</option>";
      }).join("") + "</select></label>" : "";

      var effects = level.effects.length ? '<ul class="effects">' + level.effects.map(function (e) {
        return '<li class="' + e.tone + '">' + escapeHtml(e.text) + "</li>";
      }).join("") + "</ul>" : '<p class="empty">No effects.</p>';
      var recruits = unitTiles(chain, level.units, sub);
      var garrison = unitTiles(chain, level.garrison, "");

      setTitle(shown.name);
      render(
        '<div class="crumbs"><a href="#/buildings' + (meta.subcultures[sub] ? "/" + sub : "") + '">' +
        escapeHtml(meta.subcultures[sub] ? subName(meta, sub) + " buildings" : "Buildings") + "</a> · " + escapeHtml(chain.name) + "</div>" +
        '<div class="building-head"><div><h1>' + escapeHtml(shown.name) + "</h1>" +
        '<p class="subtitle">' + escapeHtml(chain.name) + " · " + escapeHtml(chain.category) + " · Tier " + level.tier + "</p></div>" +
        selector + "</div>" +
        '<article class="unit building"><aside class="unit-side">' + buildingPicture(shown.picture, shown.name, "bld-pic large").replace(' loading="lazy"', "") +
        '<dl class="facts">' + facts.map(function (f) { return "<dt>" + f[0] + "</dt><dd>" + escapeHtml(f[1]) + "</dd>"; }).join("") + "</dl>" +
        "</aside><div class=\"unit-main\">" +
        (shown.short ? '<p class="section short">' + escapeHtml(shown.short) + "</p>" : "") +
        '<section class="section"><h2>Effects</h2>' + effects + "</section>" +
        (level.techs.length || level.from.length || level.upgrades.length ? '<section class="section"><h2>Construction</h2><dl class="facts wide">' +
          (level.from.length ? "<dt>Upgrades from</dt><dd>" + level.from.map(levelLink).join(", ") + "</dd>" : "") +
          (level.upgrades.length ? "<dt>Upgrades to</dt><dd>" + level.upgrades.map(levelLink).join(", ") + "</dd>" : "") +
          (level.techs.length ? "<dt>Needs technology</dt><dd>" + level.techs.map(function (t) {
            return '<a href="#/tech/' + encodeURIComponent(t.key) + '">' + escapeHtml(t.name) + "</a>";
          }).join(" or ") + "</dd>" : "") +
          "</dl></section>" : "") +
        (recruits ? '<section class="section"><h2>Recruits</h2>' + recruits + "</section>" :
          level.units.length ? '<section class="section"><h2>Recruits</h2><p class="empty">Nothing for this culture.</p></section>' : "") +
        (garrison ? '<section class="section"><h2>Garrison</h2>' + garrison + "</section>" : "") +
        (shown.flavour ? '<section class="section"><h2>History</h2><p class="history">' + escapeHtml(shown.flavour) + "</p></section>" : "") +
        (chain.description ? '<section class="section"><h2>About the chain</h2><p class="history">' + escapeHtml(chain.description) + "</p></section>" : "") +
        "</div></article>" +
        '<section class="section"><h2>The chain</h2><div class="tree">' + tree + "</div></section>" +
        '<p class="keys">' + escapeHtml(shown.id || level.key) + " · chain " + escapeHtml(chain.key) + "</p>"
      );

      var select = document.getElementById("f-sub");
      if (select) select.addEventListener("change", function () {
        state.sub = select.value;
        location.hash = "#/building/" + encodeURIComponent(level.key);
        if (target.id === level.key) route();
      });
    });
  }

  // --- technology trees ---------------------------------------------------------------------------------------

  var CAMPAIGN_NAMES = { main: "Grand campaign", bel: "The Last Roman", cha: "Age of Charlemagne" };

  function techIcon(icon, cls) {
    if (!icon) return '<span class="' + (cls || "tech-icon") + ' none" aria-hidden="true"></span>';
    return '<img class="' + (cls || "tech-icon") + '" src="img/techs/' + encodeURIComponent(icon) + '.png" alt="" loading="lazy">';
  }

  function techList(trees) {
    setTitle("Technologies");
    var groups = [
      ["Culture trees", trees.filter(function (t) { return t.campaign === "main" && !t.faction; })],
      ["Faction trees", trees.filter(function (t) { return t.campaign === "main" && t.faction; })],
      [CAMPAIGN_NAMES.bel, trees.filter(function (t) { return t.campaign === "bel"; })],
      [CAMPAIGN_NAMES.cha, trees.filter(function (t) { return t.campaign === "cha"; })]
    ];
    render('<div class="list-head"><h1>Technologies</h1><span class="count">' + trees.length + " trees</span></div>" +
      groups.filter(function (g) { return g[1].length; }).map(function (g) {
        return '<h2 class="spaced">' + escapeHtml(g[0]) + '</h2><div class="tech-sets">' + g[1].map(function (t) {
          return '<a class="tech-set" href="#/tech/' + encodeURIComponent(t.key) + '">' + techIcon(t.icon) +
            '<span><span class="name">' + escapeHtml(t.who) + '</span><span class="sub">' + escapeHtml(t.kind || "Technologies") +
            " · " + t.count + " technologies</span></span></a>";
        }).join("") + "</div>";
      }).join(""));
  }

  // node boxes are TREE.box wide with the icon (radius TREE.r) centred at the top
  var TREE = { col: 150, row: 92, pad: 8, box: 134, r: 22 };

  // the nodes a faction sees: its own, and the generic ones it has no own node in place of
  function visibleNodes(tree, faction) {
    var taken = {};
    tree.nodes.forEach(function (n) { if (faction && n.faction === faction) taken[n.tier + "/" + n.row] = true; });
    return tree.nodes.filter(function (n) {
      return n.faction ? n.faction === faction : !taken[n.tier + "/" + n.row];
    });
  }

  function techTree(tree, nodes, selected) {
    var byKey = {};
    nodes.forEach(function (n) { byKey[n.key] = n; });
    var tiers = Math.max.apply(null, nodes.map(function (n) { return n.tier; })) + 1;
    var rows = Math.max.apply(null, nodes.map(function (n) { return n.row; })) + 1;
    var width = tiers * TREE.col, height = rows * TREE.row;
    function x(n) { return n.tier * TREE.col + TREE.pad; }
    function y(n) { return n.row * TREE.row + TREE.pad; }
    // a point on the icon's side (1 top, 2 right, 3 bottom, 4 left), moved along the side by offset icon sizes
    function anchor(n, side, offset) {
      var cx = x(n) + TREE.box / 2, cy = y(n) + TREE.r, shift = offset * 2 * TREE.r * 0.6;
      if (side === 1) return [cx + shift, cy - TREE.r];
      if (side === 3) return [cx + shift, cy + TREE.r];
      if (side === 4) return [cx - TREE.r, cy + shift];
      return [cx + TREE.r, cy + shift];
    }
    // right-angled connectors as the game draws them: leave along the parent's side, enter along the child's
    function connector(parent, n, link) {
      var out = link[1], into = link[2];
      var s = anchor(parent, out, link[3]), e = anchor(n, into, link[4]);
      var path = "M" + s[0] + " " + s[1];
      var outVertical = out === 1 || out === 3, inVertical = into === 1 || into === 3;
      if (s[0] === e[0] || s[1] === e[1]) {
        path += " L" + e[0] + " " + e[1];
      } else if (outVertical && !inVertical) {
        path += " V" + e[1] + " H" + e[0];
      } else if (!outVertical && inVertical) {
        path += " H" + e[0] + " V" + e[1];
      } else if (outVertical) {
        var midY = (s[1] + e[1]) / 2;
        path += " V" + midY + " H" + e[0] + " V" + e[1];
      } else {
        // turn in the gap just before the child's column, so long links run along their row
        var bend = e[0] - (TREE.col - 2 * TREE.r) / 2;
        if (bend <= s[0]) bend = (s[0] + e[0]) / 2;
        path += " H" + bend + " V" + e[1] + " H" + e[0];
      }
      return path;
    }
    var lines = [], hot = [];
    nodes.forEach(function (n) {
      (n.links || []).forEach(function (link) {
        var parent = byKey[link[0]];
        if (!parent) return;
        var line = '<path d="' + connector(parent, n, link) + '"/>';
        if (selected && (n === selected || parent === selected)) hot.push(line.replace("<path", '<path class="hot"'));
        else lines.push(line);
      });
    });
    lines = lines.concat(hot);  // highlighted connectors on top
    return '<div class="tree-scroll"><div class="tech-tree" style="width:' + width + "px;height:" + height + 'px">' +
      '<svg width="' + width + '" height="' + height + '" aria-hidden="true">' + lines.join("") + "</svg>" +
      nodes.map(function (n) {
        return '<a class="tech-node' + (n === selected ? " active" : "") + '" style="left:' + x(n) + "px;top:" + y(n) +
          'px" href="#/tech/' + encodeURIComponent(n.key) + '">' + techIcon(n.icon) + '<span class="name">' +
          escapeHtml(n.name) + "</span></a>";
      }).join("") + "</div></div>";
  }

  function techPage(routes, id) {
    var set = routes[id];
    if (!set) return Promise.reject(new Error("not found"));
    return load("data/tech/" + encodeURIComponent(set) + ".json").then(function (tree) {
      function factionName(key) {
        return (tree.factions.filter(function (f) { return f.key === key; })[0] || { name: key }).name;
      }
      var node = tree.nodes.filter(function (n) { return n.key === id || n.tech === id; })[0] || null;
      // whose tree: the faction of the node asked for, else the one picked before (generic: "")
      var view = node && node.faction ? node.faction : state.techView[tree.key] || "";
      if (node && !node.faction && view && visibleNodes(tree, view).indexOf(node) < 0) view = "";
      state.techView[tree.key] = view;
      var nodes = visibleNodes(tree, view);
      var byKey = {};
      nodes.forEach(function (n) { byKey[n.key] = n; });
      function nodeLink(key) {
        var n = byKey[key];
        return n ? '<a href="#/tech/' + encodeURIComponent(key) + '">' + escapeHtml(n.name) + "</a>" : escapeHtml(key);
      }
      var detail = "";
      if (node) {
        var children = nodes.filter(function (n) { return n.parents.indexOf(node.key) >= 0; });
        var effects = node.effects.length ? '<ul class="effects">' + node.effects.map(function (e) {
          return '<li class="' + e.tone + '">' + escapeHtml(e.text) + "</li>";
        }).join("") + "</ul>" : "";
        detail =
          '<article class="tech-detail">' + techIcon(node.icon, "tech-icon large").replace(' loading="lazy"', "") + "<div>" +
          "<h1>" + escapeHtml(node.name) + "</h1>" +
          '<p class="subtitle">' + escapeHtml(tree.name) + " · Tier " + (node.tier + 1) + " · " + node.points + " research points" +
          (node.faction ? " · only " + escapeHtml(factionName(node.faction)) : "") + "</p>" +
          (node.short ? '<p class="section short">' + escapeHtml(node.short) + "</p>" : "") +
          (effects ? '<section class="section"><h2>Effects</h2>' + effects + "</section>" : "") +
          (node.buildings.length ? '<section class="section"><h2>Unlocks buildings</h2><ul class="plain-list">' +
            node.buildings.map(function (b) {
              return '<li><a href="#/building/' + encodeURIComponent(b.level) + '">' + escapeHtml(b.name) + "</a></li>";
            }).join("") + "</ul></section>" : "") +
          (node.upgrades.length ? '<section class="section"><h2>Unit upgrades</h2><ul class="plain-list">' +
            node.upgrades.map(function (u) {
              return '<li><a href="#/unit/' + encodeURIComponent(u.unit) + '">' + escapeHtml(u.name) + "</a> → " +
                '<a href="#/unit/' + encodeURIComponent(u.to) + '">' + escapeHtml(u.to_name) + "</a>" +
                (u.cost ? ' <span class="faint">(' + u.cost + ")</span>" : "") + "</li>";
            }).join("") + "</ul></section>" : "") +
          (node.parents.length || children.length ? '<section class="section"><h2>Research</h2><dl class="facts wide">' +
            (node.parents.length ? "<dt>Requires</dt><dd>" + node.parents.map(nodeLink).join(", ") + "</dd>" : "") +
            (children.length ? "<dt>Leads to</dt><dd>" + children.map(function (c) { return nodeLink(c.key); }).join(", ") + "</dd>" : "") +
            "</dl></section>" : "") +
          (node.long ? '<section class="section"><h2>History</h2><p class="history">' + escapeHtml(node.long) + "</p></section>" : "") +
          '<p class="keys">' + escapeHtml(node.tech) + (node.key !== node.tech ? " · node " + escapeHtml(node.key) : "") + "</p>" +
          "</div></article>";
      }
      var selector = tree.factions.length ? '<label class="view-as">View as <select id="f-view">' +
        '<option value="">Other factions</option>' + tree.factions.map(function (f) {
          return '<option value="' + escapeHtml(f.key) + '"' + (f.key === view ? " selected" : "") + ">" + escapeHtml(f.name) + "</option>";
        }).join("") + "</select></label>" : "";
      setTitle(node ? node.name : tree.name);
      render(
        '<div class="crumbs"><a href="#/techs">Technologies</a> · ' + escapeHtml(CAMPAIGN_NAMES[tree.campaign] || "") + "</div>" +
        (node ? "" : "<h1>" + escapeHtml(tree.name) + '</h1><p class="subtitle">' + tree.nodes.length +
          " technologies. Pick one for its effects and what it unlocks.</p>") +
        detail +
        '<section class="section"><div class="building-head"><h2>' + escapeHtml(node ? tree.name : "The tree") + "</h2>" + selector + "</div>" +
        techTree(tree, nodes, node) + "</section>"
      );
      var select = document.getElementById("f-view");
      if (select) select.addEventListener("change", function () {
        state.techView[tree.key] = select.value;
        // the selected node may not exist for the new faction: show its replacement or the tree
        var next = node && visibleNodes(tree, select.value).indexOf(node) < 0 ?
          visibleNodes(tree, select.value).filter(function (n) { return n.tier === node.tier && n.row === node.row; })[0] : node;
        var hash = "#/tech/" + encodeURIComponent(next ? next.key : tree.key);
        if (location.hash === hash) route(); else location.hash = hash;
      });
      var active = document.querySelector(".tech-node.active");
      if (active) {
        var scroller = document.querySelector(".tree-scroll");
        scroller.scrollLeft = Math.max(0, active.offsetLeft - scroller.clientWidth / 2 + 70);
      }
    });
  }

  // --- everything else the game links -------------------------------------------------------------------------

  function notCovered(route, what) {
    setTitle("Not covered yet");
    render(
      '<div class="notice"><h1>' + escapeHtml(what) + "</h1>" +
      "<p>This encyclopedia covers Fireforged's units, buildings and technologies so far. The game asked for <code>" + escapeHtml(route) + "</code>.</p>" +
      '<p><a href="https://atenc.totalwar.com/#/' + escapeHtml(route) + '" target="_blank" rel="noopener">Open it in the vanilla ' +
      'encyclopedia ↗</a> (shows the unmodded game, which may differ from Fireforged).</p>' +
      '<p><a href="#/units">Browse the units</a></p></div>'
    );
  }

  function route() {
    var path = decodeURIComponent((location.hash || "").replace(/^#\/?/, ""));
    var parts = path.split("/");
    markNav(path);
    return Promise.all([load("data/meta.json"), load("data/units.json")]).then(function (data) {
      var meta = data[0], units = data[1];
      document.getElementById("built").textContent = "Data from " + meta.built;
      switch (parts[0]) {
        case "":
          return home(meta, units);
        case "units":
          return unitList(meta, units, parts[1] || "");
        case "unit":
          return unitPage(meta, parts.slice(1).join("/")).catch(function () {
            setTitle("Unknown unit");
            render('<div class="notice"><h1>Unit not found</h1><p>No land unit <code>' + escapeHtml(parts.slice(1).join("/")) +
              '</code> in Fireforged\'s data. Ships are not covered yet.</p><p><a href="#/units">Browse the units</a></p></div>');
          });
        case "buildings":
          return load("data/buildings.json").then(function (chains) { return buildingList(meta, chains, parts[1] || ""); });
        case "building":
          return load("data/building_routes.json").then(function (routes) {
            return buildingPage(meta, routes, parts.slice(1).join("/"));
          }).catch(function () {
            setTitle("Unknown building");
            render('<div class="notice"><h1>Building not found</h1><p>No building <code>' + escapeHtml(parts.slice(1).join("/")) +
              "</code> in Fireforged's data.</p>" + '<p><a href="https://atenc.totalwar.com/#/' + escapeHtml(path) +
              '" target="_blank" rel="noopener">Try the vanilla encyclopedia ↗</a> · <a href="#/buildings">Browse the buildings</a></p></div>');
          });
        case "techs":
          return load("data/techs.json").then(techList);
        case "tech":
          return load("data/tech_routes.json").then(function (routes) {
            return techPage(routes, parts.slice(1).join("/"));
          }).catch(function () {
            setTitle("Unknown technology");
            render('<div class="notice"><h1>Technology not found</h1><p>No technology <code>' + escapeHtml(parts.slice(1).join("/")) +
              "</code> in Fireforged's data.</p>" + '<p><a href="https://atenc.totalwar.com/#/' + escapeHtml(path) +
              '" target="_blank" rel="noopener">Try the vanilla encyclopedia ↗</a> · <a href="#/techs">Browse the technologies</a></p></div>');
          });
        case "skill": case "skills": return notCovered(path, "Skills are not covered yet");
        case "character": case "characters": return notCovered(path, "Characters are not covered yet");
        case "tradition": case "traditions": return notCovered(path, "Traditions are not covered yet");
        case "manual": return notCovered(path, "The manual is not covered");
        default: return notCovered(path, "Page not found");
      }
    }).catch(function (error) {
      render('<div class="notice"><h1>Could not load the encyclopedia</h1><p>' + escapeHtml(error.message) + "</p></div>");
    });
  }

  document.getElementById("search").addEventListener("submit", function (event) { event.preventDefault(); });
  document.getElementById("search-input").addEventListener("input", function (event) {
    state.query = event.target.value.trim();
    var path = (location.hash || "").replace(/^#\/?/, "");
    if (path.indexOf("units") === 0 || path.indexOf("buildings") === 0) {
      route();
    } else {
      location.hash = path.indexOf("building") === 0 ? "#/buildings" : "#/units";
    }
  });
  window.addEventListener("hashchange", route);
  route();
})();
