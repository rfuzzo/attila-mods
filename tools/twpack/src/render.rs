// Renders a decoded UI layout as a static HTML page (absolutely positioned boxes), for looking at a layout without
// starting the game: `twpack ui render`. Approximate on purpose: boxes at their design-size positions, state images
// (tiled / nine-patch / stretched) and text. No fonts, no docking for other screen sizes, no animations.
//
// Positions: `offset` relative to the parent, at the design size. (`docking` + `dock_offset` give the same position
// in about 94% of components, the rest is rounding or stale; the dock only matters when the parent is resized.)

use std::collections::BTreeSet;
use std::fmt::Write;

use crate::uic::{Layout, State, Uic};

// Stacking: a lower `priority` is in front (the parchment has 12, the lists 0, a title 45 in front of its plaque 50).
pub struct Options {
    /// Render the component with this name (first match, depth first) as the page root
    pub only: Option<String>,
    /// Show this state wherever a component has it (otherwise each component's default state)
    pub state: Option<String>,
    /// Also show components whose `visible` flag is off (the game switches many of them on from script)
    pub show_hidden: bool,
    pub scale: f32,
}

pub struct Page {
    pub html: String,
    /// Image paths the page refers to, as written in the layout
    pub images: BTreeSet<String>,
}

pub fn render(layout: &Layout, title: &str, opts: &Options) -> Result<Page, String> {
    let root = match &opts.only {
        Some(name) => find(&layout.root, name).ok_or_else(|| format!("no component named {:?}", name))?,
        None => &layout.root,
    };
    // The page covers everything drawn, including what sticks out of the root (title plaques sit above their panel).
    let mut bbox = (0, 0, 0, 0);
    extent(root, 0, 0, opts, &mut bbox);
    let (w, h) = (bbox.2 - bbox.0, bbox.3 - bbox.1);
    let mut body = String::new();
    let mut images = BTreeSet::new();
    component(root, opts, Some((-bbox.0, -bbox.1)), &mut body, &mut images, 1);
    let html = format!(
        "<!doctype html>\n<meta charset=\"utf-8\">\n<title>{title}</title>\n<style>{CSS}</style>\n\
         <div id=\"screen\" style=\"width:{w}px;height:{h}px;transform:scale({scale});transform-origin:0 0\">\n{body}</div>\n",
        title = esc(title),
        scale = opts.scale,
    );
    Ok(Page { html, images })
}

/// Grows `bbox` (min x, min y, max x, max y) by the visible components below `u`, whose top left is at (x, y).
fn extent(u: &Uic, x: i32, y: i32, opts: &Options, bbox: &mut (i32, i32, i32, i32)) {
    if u.flags.visible.0 == 0 && !opts.show_hidden {
        return;
    }
    let (w, h) = pick(u, opts).map(|s| (s.bounds.0[0], s.bounds.0[1])).unwrap_or((0, 0));
    *bbox = (bbox.0.min(x), bbox.1.min(y), bbox.2.max(x + w), bbox.3.max(y + h));
    for c in &u.children {
        extent(c, x + c.offset.0[0], y + c.offset.0[1], opts, bbox);
    }
}

fn find<'a>(u: &'a Uic, name: &str) -> Option<&'a Uic> {
    if u.name == name {
        return Some(u);
    }
    u.children.iter().find_map(|c| find(c, name))
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// The state to draw: the requested one, else the default state, else the first.
fn pick<'a>(u: &'a Uic, opts: &Options) -> Option<&'a State> {
    if let Some(name) = &opts.state {
        if let Some(s) = u.states.iter().find(|s| &s.name == name) {
            return Some(s);
        }
    }
    if u.default_state.b != [0; 4] {
        if let Some(s) = u.states.iter().find(|s| s.uid.b == u.default_state.b) {
            return Some(s);
        }
    }
    u.states.first()
}

/// `rrggbbaa` (alpha last, as in the files) as a CSS colour. The channel order is assumed to be RGB.
fn rgba(c: &[u8; 4]) -> String {
    format!("rgba({},{},{},{:.3})", c[0], c[1], c[2], c[3] as f32 / 255.0)
}

fn component(u: &Uic, opts: &Options, at: Option<(i32, i32)>, out: &mut String, images: &mut BTreeSet<String>, depth: usize) {
    let visible = u.flags.visible.0 != 0;
    if !visible && !opts.show_hidden {
        return;
    }
    let state = pick(u, opts);
    let (w, h) = state.map(|s| (s.bounds.0[0], s.bounds.0[1])).unwrap_or((0, 0));
    let (x, y) = at.unwrap_or((u.offset.0[0], u.offset.0[1]));
    let mut style = format!("left:{}px;top:{}px;width:{}px;height:{}px;z-index:{}", x, y, w, h, -u.priority);
    if u.flags.clip_children.0 != 0 {
        style += ";overflow:hidden";
    }
    let class = if visible { "c" } else { "c hidden" };
    let _ = write!(out, "{}<div class=\"{}\" data-name=\"{}\" style=\"{}\">\n", "  ".repeat(depth), class, esc(&u.name), style);
    if let Some(state) = state {
        for m in &state.image_metrics {
            metric(u, m, out, images, depth + 1);
        }
        let text = if state.text.is_empty() { &state.text_label } else { &state.text };
        if !text.is_empty() {
            let (halign, valign) = (["flex-start", "center", "flex-end"][state.text_halign.clamp(0, 2) as usize], ["flex-start", "flex-start", "center", "flex-end"][state.text_valign.clamp(0, 3) as usize]);
            let _ = write!(
                out,
                "{}<div class=\"t\" style=\"justify-content:{};align-items:{};font-size:{}px;color:{};padding:{}px {}px {}px {}px\">{}</div>\n",
                "  ".repeat(depth + 1),
                halign,
                valign,
                state.font_size.max(6),
                rgba(&state.font_colour.0),
                state.text_offset.0[2].max(0),
                state.text_offset.0[1].max(0),
                state.text_offset.0[3].max(0),
                state.text_offset.0[0].max(0),
                esc(text).replace(" || ", "<br>")
            );
        }
    }
    for c in &u.children {
        component(c, opts, None, out, images, depth + 1);
    }
    let _ = writeln!(out, "{}</div>", "  ".repeat(depth));
}

fn metric(u: &Uic, m: &crate::uic::ImageMetric, out: &mut String, images: &mut BTreeSet<String>, depth: usize) {
    let image = u.images.iter().find(|i| i.uid.b == m.image_uid.b);
    let (mut w, mut h) = (m.bounds.0[0], m.bounds.0[1]);
    if let Some(i) = image {
        if w <= 0 || h <= 0 {
            (w, h) = (i.width, i.height);
        }
    }
    let mut style = format!("left:{}px;top:{}px;width:{}px;height:{}px", m.offset.0[0], m.offset.0[1], w, h);
    let alpha = m.colour.0[3] as f32 / 255.0;
    if alpha < 1.0 {
        let _ = write!(style, ";opacity:{:.3}", alpha);
    }
    let flip = match (m.x_flipped != 0, m.y_flipped != 0) {
        (true, true) => Some("scale(-1,-1)"),
        (true, false) => Some("scale(-1,1)"),
        (false, true) => Some("scale(1,-1)"),
        _ => None,
    };
    if let Some(flip) = flip {
        let _ = write!(style, ";transform:{}", flip);
    }
    match image.filter(|i| !i.path.is_empty()) {
        Some(i) => {
            let path = i.path.replace('\\', "/").to_lowercase();
            let url = format!("url('{}')", path.replace('\'', "%27"));
            images.insert(path);
            let [top, right, bottom, left] = m.margin.0;
            if m.margin.0.iter().any(|v| *v > 0.0) {
                // Nine-patch: the margins are in texture pixels; the middle tiles or stretches.
                let repeat = if m.tile != 0 { "repeat" } else { "stretch" };
                let _ = write!(
                    style,
                    ";box-sizing:border-box;border-style:solid;border-width:{top}px {right}px {bottom}px {left}px;border-image:{url} {top} {right} {bottom} {left} fill / {top}px {right}px {bottom}px {left}px {repeat}",
                );
            } else if m.tile != 0 {
                let _ = write!(style, ";background:{url} repeat 0 0");
            } else {
                let _ = write!(style, ";background:{url} no-repeat 0 0 / 100% 100%");
            }
            let _ = writeln!(out, "{}<div class=\"i\" style=\"{}\"></div>", "  ".repeat(depth), style);
        }
        // An image the game fills in from script, or one that isn't in the layout.
        None => {
            let _ = writeln!(out, "{}<div class=\"i dyn\" style=\"{}\"></div>", "  ".repeat(depth), style);
        }
    }
}

const CSS: &str = "\
html{background:#1b1b1b}body{margin:0}\
#screen{position:relative;background:#3a3a3a;font-family:Georgia,'Times New Roman',serif}\
.c{position:absolute;box-sizing:border-box;isolation:isolate}\
.c.hidden{outline:1px dashed #f0f;opacity:.6}\
.i{position:absolute;z-index:-1000000}\
.i.dyn{outline:1px dotted rgba(255,255,255,.25)}\
.t{position:absolute;inset:0;display:flex;box-sizing:border-box;z-index:-999999;white-space:pre-wrap;overflow:hidden;line-height:1.1}\
";
