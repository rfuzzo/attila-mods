// Fireforged Empire encyclopedia. The game opens <base>#/unit/<main unit key> (and #/building/..., #/tech/...,
// #/skill/..., #/character/..., #/tradition/..., #/manual/...), so everything routes on location.hash.
// Data: data/units.json (the list), data/unit/<key>.json (one unit), data/meta.json (cultures, stat maxima).
(function () {
  "use strict";

  var view = document.getElementById("view");
  var cache = {};
  var state = { campaign: "main", category: "", query: "", unused: false };

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
    for (var i = 0; i < links.length; i++) {
      links[i].classList.toggle("active", route.indexOf("unit") === 0 && links[i].getAttribute("href") === "#/units");
    }
  }

  // --- home ---------------------------------------------------------------------------------------------------

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
      'the mod\'s own historical descriptions. The unit links in the game lead here when the ' +
      '<code>fireforged_encyclopedia</code> TWASE mod is enabled. For screenshots and the authors\' notes on each ' +
      'culture, follow the links to the <a href="https://late-roman.ru/fireforged-empire/units/" target="_blank" ' +
      'rel="noopener">mod website</a>.</p></section>' +
      '<h2>Units by culture</h2><div class="culture-grid">' + tiles + '</div>'
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
      var buildings = u.buildings.map(function (b) { return "<li>" + escapeHtml(b) + "</li>"; }).join("");
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
        (buildings ? '<section class="section"><h2>Recruited in</h2><ul class="plain-list">' + buildings + "</ul></section>" : "") +
        '<section class="section links"><h2>On the mod website</h2>' + links + "</section>" +
        '<p class="keys">' + escapeHtml(u.key) + (u.land_unit !== u.key ? " · land unit " + escapeHtml(u.land_unit) : "") + "</p>" +
        "</div></article>"
      );
    });
  }

  // --- everything else the game links -------------------------------------------------------------------------

  function notCovered(route, what) {
    setTitle("Not covered yet");
    render(
      '<div class="notice"><h1>' + escapeHtml(what) + "</h1>" +
      "<p>This encyclopedia covers Fireforged's units so far. The game asked for <code>" + escapeHtml(route) + "</code>.</p>" +
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
        case "building": case "buildings": return notCovered(path, "Buildings are not covered yet");
        case "tech": case "techs": return notCovered(path, "Technologies are not covered yet");
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
    if (path.indexOf("units") === 0) {
      route();
    } else {
      location.hash = "#/units";
    }
  });
  window.addEventListener("hashchange", route);
  route();
})();
