// Attila's binary UI layout files (`ui/**/<name>`, no extension, start with `Version0NN`), and a text form of them.
//
// Binary layout after the parser in https://github.com/Cpecific/twwh2_ctm (class.php, GPL-3.0, reads versions 70
// to 133), pruned to what Attila ships: 92 to 99 (about 40 files of 77 to 91 exist, unsupported). Fields whose
// meaning isn't known stay opaque hex blobs, so decode followed by encode is byte-identical (`twpack ui check`).
// Reading and writing go through one description of the layout (`Io`), so the two can't drift apart.
//
// Strings: `str` is a u16 byte length + bytes, `wstr` a u16 character count + UTF-16LE. Integers are little-endian.
//
// Text form (YAML, `to_text` / `from_text`): every field that equals its default is left out, small number groups
// are one line ("1280 1024"), and references between uids are names: a state refers to its image by path (or `#index`),
// `default_state` and mouse events refer to states by name, animation triggers to components by name. A missing node
// uid is generated on import, so new components can be written without one (`to_text` can leave them all out).

use std::collections::{HashMap, HashSet};
use std::fmt::Display;
use std::str::FromStr;

use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

pub const MIN_VERSION: u32 = 92;
pub const MAX_VERSION: u32 = 99;

// ---------------------------------------------------------------------------------------------------------------
// Value types
// ---------------------------------------------------------------------------------------------------------------

fn is_default<T: Default + PartialEq>(t: &T) -> bool {
    *t == T::default()
}

fn to_hex(b: &[u8]) -> String {
    b.iter().map(|b| format!("{:02x}", b)).collect()
}

fn from_hex(s: &str) -> std::result::Result<Vec<u8>, String> {
    if s.len() % 2 != 0 || !s.is_ascii() {
        return Err(format!("bad hex string {:?}", s));
    }
    (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(|_| format!("bad hex string {:?}", s))).collect()
}

/// `N` opaque bytes, shown as hex; the default is `N` bytes of `D`.
#[derive(Clone, Debug, PartialEq)]
pub struct Hex<const N: usize, const D: u8 = 0>(pub [u8; N]);

impl<const N: usize, const D: u8> Default for Hex<N, D> {
    fn default() -> Self {
        Hex([D; N])
    }
}
impl<const N: usize, const D: u8> Serialize for Hex<N, D> {
    fn serialize<S: Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        s.serialize_str(&to_hex(&self.0))
    }
}
impl<'de, const N: usize, const D: u8> Deserialize<'de> for Hex<N, D> {
    fn deserialize<De: Deserializer<'de>>(d: De) -> std::result::Result<Self, De::Error> {
        let bytes = from_hex(&String::deserialize(d)?).map_err(serde::de::Error::custom)?;
        let len = bytes.len();
        <[u8; N]>::try_from(bytes).map(Hex).map_err(|_| serde::de::Error::custom(format!("expected {} bytes of hex, got {}", N, len)))
    }
}

/// Opaque bytes whose length depends on the version or on another field. Empty means all zeros.
#[derive(Default, Clone, Debug, PartialEq)]
pub struct Bytes(pub Vec<u8>);

impl Serialize for Bytes {
    fn serialize<S: Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        s.serialize_str(&to_hex(&self.0))
    }
}
impl<'de> Deserialize<'de> for Bytes {
    fn deserialize<De: Deserializer<'de>>(d: De) -> std::result::Result<Self, De::Error> {
        from_hex(&String::deserialize(d)?).map(Bytes).map_err(serde::de::Error::custom)
    }
}

/// One byte flag; the default is `D`.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Byte<const D: u8>(pub u8);

impl<const D: u8> Default for Byte<D> {
    fn default() -> Self {
        Byte(D)
    }
}

pub trait Num: Copy + Default + Display + FromStr {
    fn to_b(self) -> [u8; 4];
    fn from_b(b: [u8; 4]) -> Self;
}
impl Num for i32 {
    fn to_b(self) -> [u8; 4] {
        self.to_le_bytes()
    }
    fn from_b(b: [u8; 4]) -> Self {
        i32::from_le_bytes(b)
    }
}
impl Num for f32 {
    fn to_b(self) -> [u8; 4] {
        self.to_le_bytes()
    }
    fn from_b(b: [u8; 4]) -> Self {
        f32::from_le_bytes(b)
    }
}

/// A fixed group of numbers, shown on one line: `1280 1024`.
#[derive(Clone, Debug, PartialEq)]
pub struct Nums<T, const N: usize>(pub [T; N]);

impl<T: Num, const N: usize> Default for Nums<T, N> {
    fn default() -> Self {
        Nums([T::default(); N])
    }
}
impl<T: Num, const N: usize> Serialize for Nums<T, N> {
    fn serialize<S: Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        s.serialize_str(&self.0.iter().map(|n| n.to_string()).collect::<Vec<_>>().join(" "))
    }
}
impl<'de, T: Num, const N: usize> Deserialize<'de> for Nums<T, N> {
    fn deserialize<De: Deserializer<'de>>(d: De) -> std::result::Result<Self, De::Error> {
        let text = String::deserialize(d)?;
        let nums: Vec<T> = text.split_whitespace().map(|n| n.parse().map_err(|_| serde::de::Error::custom(format!("bad number {:?} in {:?}", n, text)))).collect::<std::result::Result<_, _>>()?;
        let len = nums.len();
        <[T; N]>::try_from(nums).map(Nums).map_err(|_| serde::de::Error::custom(format!("expected {} numbers, got {} in {:?}", N, len, text)))
    }
}

/// A 4 byte id of a component, state or image, or a reference to one. In the text form a reference is a name (`sym`)
/// that `from_text` turns back into the id.
#[derive(Default, Clone, Debug, PartialEq)]
pub struct Uid {
    pub b: [u8; 4],
    pub sym: Option<String>,
}

fn is_hex8(s: &str) -> bool {
    s.len() == 8 && s.bytes().all(|c| c.is_ascii_hexdigit())
}

impl Serialize for Uid {
    fn serialize<S: Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        match &self.sym {
            Some(sym) => s.serialize_str(sym),
            None => s.serialize_str(&to_hex(&self.b)),
        }
    }
}
impl<'de> Deserialize<'de> for Uid {
    fn deserialize<De: Deserializer<'de>>(d: De) -> std::result::Result<Self, De::Error> {
        let text = String::deserialize(d)?;
        if is_hex8(&text) {
            let b = from_hex(&text).map_err(serde::de::Error::custom)?;
            Ok(Uid { b: b.try_into().unwrap(), sym: None })
        } else {
            Ok(Uid { b: [0; 4], sym: Some(text) })
        }
    }
}

/// Defines a struct of single-byte fields (stored as consecutive bytes in the file).
macro_rules! byte_struct {
    ($(#[$m:meta])* $name:ident { $($(#[$fm:meta])* $f:ident : $d:literal),* $(,)? }) => {
        $(#[$m])*
        #[derive(Default, Clone, Debug, PartialEq, Serialize, Deserialize)]
        #[serde(default)]
        pub struct $name { $( $(#[$fm])* #[serde(skip_serializing_if = "is_default")] pub $f: Byte<$d>, )* }
        impl ByteStruct for $name {
            fn to_bytes(&self) -> Vec<u8> {
                vec![$(self.$f.0),*]
            }
            fn from_bytes(&mut self, b: &[u8]) {
                let mut i = 0;
                $( self.$f.0 = b[i]; i += 1; )*
                let _ = i;
            }
        }
    };
}

/// Defines a record: every field falls back to its default when missing and is left out when equal to it.
macro_rules! record {
    ($(#[$m:meta])* $name:ident { $($(#[$fm:meta])* $f:ident : $t:ty),* $(,)? }) => {
        $(#[$m])*
        #[derive(Default, Clone, Debug, PartialEq, Serialize, Deserialize)]
        #[serde(default)]
        pub struct $name { $( $(#[$fm])* #[serde(skip_serializing_if = "is_default")] pub $f: $t, )* }
    };
}

trait ByteStruct {
    fn to_bytes(&self) -> Vec<u8>;
    fn from_bytes(&mut self, b: &[u8]);
}

// ---------------------------------------------------------------------------------------------------------------
// The layout
// ---------------------------------------------------------------------------------------------------------------

#[derive(Default, Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Layout {
    pub version: u32,
    pub root: Uic,
}

byte_struct!(
    /// 12 bytes. Named after the reference parser's notes and the components that set them (`moveable` is set on
    /// slider handles, `clip_children` on `list_clip`s); the names of the unnamed ones are their byte index.
    Flags {
        allow_h_resize: 1,
        allow_v_resize: 1,
        moveable: 0,
        flag3: 0,
        flag4: 0,
        flag5: 0,
        visible: 1,
        clip_children: 0,
        clip_image: 0,
        flag9: 0,
        flag10: 0,
        flag11: 1,
    }
);

byte_struct!(
    /// 4 bytes of a state. `interactive` is set on buttons and everything with mouse states, `mouse_on` is the
    /// reference parser's "triggers ComponentMouseOn".
    Focus {
        interactive: 0,
        mouse_on: 0,
        unk2: 0,
        unk3: 0,
    }
);

record!(
    /// A component: a panel, button, label ...
    Uic {
        name: String,
        uid: Uid,
        /// What the game treats it as: `Button`, `TextButton`, `VSlider`, `List`, `Listview`, ...
        class: String,
        /// Relative to the parent
        offset: Nums<i32, 2>,
        flags: Flags,
        tooltip_text: String,
        tooltip_id: String,
        docking: i32,
        dock_offset: Nums<i32, 2>,
        b3: Hex<1>,
        /// State (by name) it starts in; none = the first
        default_state: Uid,
        images: Vec<Image>,
        mask_image: Uid,
        b5: Hex<4>,
        states: Vec<State>,
        /// Key / value pairs the class reads (`stepSize`, `minValue`, ...)
        properties: Vec<Property>,
        /// Draw order among siblings
        priority: i32,
        funcs: Vec<Func>,
        children: Vec<Uic>,
        tail: Tail,
    }
);

record!(
    Image {
        path: String,
        uid: Uid,
        width: i32,
        height: i32,
        extra: Hex<1>,
    }
);

record!(
    Property {
        key: String,
        value: String,
    }
);

record!(
    State {
        name: String,
        uid: Uid,
        bounds: Nums<i32, 2>,
        text: String,
        tooltip: String,
        text_bounds: Nums<i32, 2>,
        /// 0 left, 1 center, 2 right
        text_halign: i32,
        /// 1 top, 2 middle, 3 bottom
        text_valign: i32,
        b1: Hex<1, 1>,
        text_label: String,
        text_localised: Hex<2>,
        localised: String,
        tooltip_id: String,
        b5: String,
        font_name: String,
        font_size: i32,
        font_leading: i32,
        font_tracking: i32,
        font_colour: Hex<4>,
        font_category: String,
        /// left, right, top, bottom
        text_offset: Nums<i32, 4>,
        focus: Focus,
        shader: String,
        shader_vars: Nums<f32, 4>,
        text_shader: String,
        text_shader_vars: Nums<f32, 4>,
        image_metrics: Vec<ImageMetric>,
        /// Where the state sits in the state editor
        editor_pos: Nums<i32, 2>,
        mouse: Vec<Mouse>,
    }
);

record!(
    /// Places one of the component's images in a state.
    ImageMetric {
        /// The image, by path (or `#index` if the path is empty or not unique)
        image_uid: Uid,
        offset: Nums<i32, 2>,
        bounds: Nums<i32, 2>,
        colour: Hex<4>,
        tile: u8,
        x_flipped: u8,
        y_flipped: u8,
        /// 1 top left .. 9 bottom right (3x3 grid), 0 span
        dockpoint: i32,
        dock_offset: Nums<i32, 2>,
        can_resize_height: u8,
        can_resize_width: u8,
        rotation_angle: f32,
        pivot: Nums<f32, 2>,
        shader: String,
        rotation_axis: Nums<f32, 3>,
        b4: Hex<4>,
        /// top, right, bottom, left (nine-patch margins)
        margin: Nums<f32, 4>,
    }
);

record!(
    Mouse {
        /// 0 enter, 1 out, 2 down, 3 up (click), 8 blur, 9, 11
        event: i32,
        /// The state it switches to, by name
        state_uid: Uid,
        params: Nums<i32, 2>,
        sounds: Vec<Sound>,
    }
);

record!(
    Sound {
        b0: Hex<4>,
        s0: String,
        s1: String,
        s2: String,
    }
);

record!(
    /// An animation group (`show`, `hide`, `fade_in`, ...)
    Func {
        name: String,
        b0: Hex<2>,
        anims: Vec<Anim>,
        sound: String,
    }
);

record!(
    Anim {
        offset: Nums<f32, 2>,
        bounds: Nums<i32, 2>,
        colour: Hex<4>,
        shader_vars: Nums<f32, 4>,
        rotation_angle: f32,
        image_index: Nums<i32, 2>,
        interpolation_time: i32,
        interpolation_property_mask: i32,
        easing_weight: f32,
        easing_curve: String,
        triggers: Vec<Trigger>,
        movement_absolute: Hex<1>,
    }
);

record!(
    Trigger {
        /// The component, by name
        uid: Uid,
        animation: String,
        state: String,
        property: String,
    }
);

record!(
    /// Everything after the children: the layout engine (list, table, ...) or a button group, and 3D model attachments.
    Tail {
        b0: Hex<1>,
        /// "", `List`, `HorizontalList`, `RadialList`, `Table`, or a group name such as `grp_gw_generic_button`
        kind: String,
        list: Option<List>,
        radial: Option<Radial>,
        table: Option<Table>,
        s: String,
        ids: Option<Vec<Hex<4>>>,
        v97: Option<Blob97>,
        v97_end: Hex<4>,
        model: Option<Model3d>,
        end: Bytes,
    }
);

record!(
    List {
        floats: Vec<f32>,
        a: i32,
        b: i32,
        flag: Hex<1>,
        c: i32,
        /// v92-96: 3 bytes (8 at v96); v97-99: 6 bytes, then `ext_str` and `ext_tail`
        ext: Bytes,
        ext_str: String,
        ext_tail: Hex<5>,
    }
);

record!(
    Radial {
        values: Nums<f32, 4>,
        b: Hex<3>,
    }
);

record!(
    Table {
        rows: Vec<Vec<Cell>>,
        end: Hex<2>,
    }
);

record!(
    Cell {
        a: f32,
        b: f32,
        rest: Hex<12>,
    }
);

record!(
    Blob97 {
        a: i32,
        n: i32,
        blob: Bytes,
    }
);

record!(
    Model3d {
        s: String,
        head: Hex<74>,
        models: Vec<ModelEntry>,
    }
);

record!(
    ModelEntry {
        s0: String,
        s1: String,
        b: Hex<1>,
        anims: Vec<ModelAnim>,
    }
);

record!(
    ModelAnim {
        s0: String,
        s1: String,
        b: Hex<4>,
    }
);

// ---------------------------------------------------------------------------------------------------------------
// One description for reading and writing
// ---------------------------------------------------------------------------------------------------------------

trait Io: Sized {
    /// Fixed-size bytes: filled when reading, written when writing.
    fn bytes(&mut self, b: &mut [u8]) -> Result<()>;
    /// Variable-length string: u16 length + bytes (`wide`: characters, UTF-16LE).
    fn string(&mut self, s: &mut String, wide: bool) -> Result<()>;
    /// An element count: read from the file / written from `n`.
    fn count(&mut self, n: usize) -> Result<usize>;
    fn pos(&self) -> usize;
    fn reading(&self) -> bool;

    fn i32(&mut self, v: &mut i32) -> Result<()> {
        let mut b = v.to_le_bytes();
        self.bytes(&mut b)?;
        *v = i32::from_le_bytes(b);
        Ok(())
    }
    fn f32(&mut self, v: &mut f32) -> Result<()> {
        let mut b = v.to_le_bytes();
        self.bytes(&mut b)?;
        *v = f32::from_le_bytes(b);
        Ok(())
    }
    fn u8(&mut self, v: &mut u8) -> Result<()> {
        let mut b = [*v];
        self.bytes(&mut b)?;
        *v = b[0];
        Ok(())
    }
    fn hex<const N: usize, const D: u8>(&mut self, h: &mut Hex<N, D>) -> Result<()> {
        self.bytes(&mut h.0)
    }
    /// `n` bytes; empty = zeros.
    fn var(&mut self, h: &mut Bytes, n: usize) -> Result<()> {
        if self.reading() {
            let mut b = vec![0; n];
            self.bytes(&mut b)?;
            h.0 = if b.iter().all(|x| *x == 0) { vec![] } else { b };
        } else {
            let mut b = match h.0.len() {
                0 => vec![0; n],
                len if len == n => h.0.clone(),
                len => bail!("expected {} bytes, got {}", n, len),
            };
            self.bytes(&mut b)?;
        }
        Ok(())
    }
    fn uid(&mut self, u: &mut Uid) -> Result<()> {
        if let Some(sym) = &u.sym {
            bail!("unresolved reference {:?}", sym);
        }
        self.bytes(&mut u.b)
    }
    fn nums<T: Num, const N: usize>(&mut self, v: &mut Nums<T, N>) -> Result<()> {
        for x in v.0.iter_mut() {
            let mut b = x.to_b();
            self.bytes(&mut b)?;
            *x = T::from_b(b);
        }
        Ok(())
    }
    fn flags<S: ByteStruct>(&mut self, s: &mut S) -> Result<()> {
        let mut b = s.to_bytes();
        self.bytes(&mut b)?;
        s.from_bytes(&b);
        Ok(())
    }
    fn str(&mut self, s: &mut String) -> Result<()> {
        self.string(s, false)
    }
    fn wstr(&mut self, s: &mut String) -> Result<()> {
        self.string(s, true)
    }
    /// A counted list; `f` describes one element.
    fn list<T: Default>(&mut self, v: &mut Vec<T>, mut f: impl FnMut(&mut Self, &mut T) -> Result<()>) -> Result<()> {
        let n = self.count(v.len())?;
        v.resize_with(n, T::default);
        v.iter_mut().try_for_each(|x| f(self, x))
    }
    /// A flag byte (0 or 1) followed by the value if it's 1.
    fn flagged<T: Default>(&mut self, o: &mut Option<T>, f: impl FnOnce(&mut Self, &mut T) -> Result<()>) -> Result<()> {
        let mut b = [o.is_some() as u8];
        self.bytes(&mut b)?;
        match b[0] {
            0 => *o = None,
            1 => f(self, o.get_or_insert_with(T::default))?,
            n => bail!("flag byte {} at {:#x} (expected 0 or 1)", n, self.pos() - 1),
        }
        Ok(())
    }
}

struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl Io for Reader<'_> {
    fn bytes(&mut self, b: &mut [u8]) -> Result<()> {
        let end = self.pos + b.len();
        let src = self.data.get(self.pos..end).ok_or_else(|| anyhow!("unexpected end of file at {:#x} (need {} bytes)", self.pos, b.len()))?;
        b.copy_from_slice(src);
        self.pos = end;
        Ok(())
    }
    fn string(&mut self, s: &mut String, wide: bool) -> Result<()> {
        let mut len = [0u8; 2];
        self.bytes(&mut len)?;
        let len = u16::from_le_bytes(len) as usize;
        let mut buf = vec![0u8; len * if wide { 2 } else { 1 }];
        self.bytes(&mut buf)?;
        *s = if wide {
            String::from_utf16(&buf.chunks(2).map(|c| u16::from_le_bytes([c[0], c[1]])).collect::<Vec<_>>())?
        } else {
            String::from_utf8(buf).map_err(|e| anyhow!("string at {:#x} isn't UTF-8: {}", self.pos, e))?
        };
        Ok(())
    }
    fn count(&mut self, _: usize) -> Result<usize> {
        let mut v = 0;
        self.i32(&mut v)?;
        // Every element takes at least a byte, so this stops garbage from allocating gigabytes.
        if v < 0 || v as usize > self.data.len() - self.pos {
            bail!("implausible count {} at {:#x}", v, self.pos - 4);
        }
        Ok(v as usize)
    }
    fn pos(&self) -> usize {
        self.pos
    }
    fn reading(&self) -> bool {
        true
    }
}

#[derive(Default)]
struct Writer(Vec<u8>);

impl Io for Writer {
    fn bytes(&mut self, b: &mut [u8]) -> Result<()> {
        self.0.extend_from_slice(b);
        Ok(())
    }
    fn string(&mut self, s: &mut String, wide: bool) -> Result<()> {
        if wide {
            let units: Vec<u16> = s.encode_utf16().collect();
            if units.len() > u16::MAX as usize {
                bail!("string too long");
            }
            self.0.extend_from_slice(&(units.len() as u16).to_le_bytes());
            units.iter().for_each(|u| self.0.extend_from_slice(&u.to_le_bytes()));
        } else {
            if s.len() > u16::MAX as usize {
                bail!("string too long");
            }
            self.0.extend_from_slice(&(s.len() as u16).to_le_bytes());
            self.0.extend_from_slice(s.as_bytes());
        }
        Ok(())
    }
    fn count(&mut self, n: usize) -> Result<usize> {
        self.0.extend_from_slice(&(n as i32).to_le_bytes());
        Ok(n)
    }
    fn pos(&self) -> usize {
        self.0.len()
    }
    fn reading(&self) -> bool {
        false
    }
}

// ---------------------------------------------------------------------------------------------------------------
// The layout, version 92 to 99
// ---------------------------------------------------------------------------------------------------------------

fn uic<I: Io>(io: &mut I, v: u32, u: &mut Uic) -> Result<()> {
    io.uid(&mut u.uid)?;
    io.str(&mut u.name)?;
    io.str(&mut u.class)?;
    io.nums(&mut u.offset)?;
    io.flags(&mut u.flags)?;
    io.wstr(&mut u.tooltip_text)?;
    io.wstr(&mut u.tooltip_id)?;
    io.i32(&mut u.docking)?;
    io.nums(&mut u.dock_offset)?;
    io.hex(&mut u.b3)?;
    io.uid(&mut u.default_state)?;
    io.list(&mut u.images, |io, i| image(io, i))?;
    io.uid(&mut u.mask_image)?;
    io.hex(&mut u.b5)?;
    io.list(&mut u.states, |io, s| state(io, s))?;
    io.list(&mut u.properties, |io, p| {
        io.str(&mut p.key)?;
        io.str(&mut p.value)
    })?;
    io.i32(&mut u.priority)?;
    io.list(&mut u.funcs, |io, f| func(io, f))?;
    io.list(&mut u.children, |io, c| uic(io, v, c))?;
    tail(io, v, &mut u.tail)
}

fn image<I: Io>(io: &mut I, i: &mut Image) -> Result<()> {
    io.uid(&mut i.uid)?;
    io.str(&mut i.path)?;
    io.i32(&mut i.width)?;
    io.i32(&mut i.height)?;
    io.hex(&mut i.extra)
}

fn state<I: Io>(io: &mut I, s: &mut State) -> Result<()> {
    io.uid(&mut s.uid)?;
    io.str(&mut s.name)?;
    io.nums(&mut s.bounds)?;
    io.wstr(&mut s.text)?;
    io.wstr(&mut s.tooltip)?;
    io.nums(&mut s.text_bounds)?;
    io.i32(&mut s.text_halign)?;
    io.i32(&mut s.text_valign)?;
    io.hex(&mut s.b1)?;
    io.wstr(&mut s.text_label)?;
    io.hex(&mut s.text_localised)?;
    io.wstr(&mut s.localised)?;
    io.wstr(&mut s.tooltip_id)?;
    io.str(&mut s.b5)?;
    io.str(&mut s.font_name)?;
    io.i32(&mut s.font_size)?;
    io.i32(&mut s.font_leading)?;
    io.i32(&mut s.font_tracking)?;
    io.hex(&mut s.font_colour)?;
    io.str(&mut s.font_category)?;
    io.nums(&mut s.text_offset)?;
    io.flags(&mut s.focus)?;
    io.str(&mut s.shader)?;
    io.nums(&mut s.shader_vars)?;
    io.str(&mut s.text_shader)?;
    io.nums(&mut s.text_shader_vars)?;
    io.list(&mut s.image_metrics, |io, b| image_metric(io, b))?;
    io.nums(&mut s.editor_pos)?;
    io.list(&mut s.mouse, |io, m| mouse(io, m))
}

fn image_metric<I: Io>(io: &mut I, b: &mut ImageMetric) -> Result<()> {
    io.uid(&mut b.image_uid)?;
    io.nums(&mut b.offset)?;
    io.nums(&mut b.bounds)?;
    io.hex(&mut b.colour)?;
    io.u8(&mut b.tile)?;
    io.u8(&mut b.x_flipped)?;
    io.u8(&mut b.y_flipped)?;
    io.i32(&mut b.dockpoint)?;
    io.nums(&mut b.dock_offset)?;
    io.u8(&mut b.can_resize_height)?;
    io.u8(&mut b.can_resize_width)?;
    io.f32(&mut b.rotation_angle)?;
    io.nums(&mut b.pivot)?;
    // The shader name and the rotation axis swapped places in v103; Attila only has the old order.
    io.str(&mut b.shader)?;
    io.nums(&mut b.rotation_axis)?;
    io.hex(&mut b.b4)?;
    io.nums(&mut b.margin)
}

fn mouse<I: Io>(io: &mut I, m: &mut Mouse) -> Result<()> {
    io.i32(&mut m.event)?;
    io.uid(&mut m.state_uid)?;
    io.nums(&mut m.params)?;
    io.list(&mut m.sounds, |io, s| {
        io.hex(&mut s.b0)?;
        io.str(&mut s.s0)?;
        io.str(&mut s.s1)?;
        io.str(&mut s.s2)
    })
}

fn func<I: Io>(io: &mut I, f: &mut Func) -> Result<()> {
    io.str(&mut f.name)?;
    io.hex(&mut f.b0)?;
    io.list(&mut f.anims, |io, a| anim(io, a))?;
    io.str(&mut f.sound)
}

fn anim<I: Io>(io: &mut I, a: &mut Anim) -> Result<()> {
    io.nums(&mut a.offset)?;
    io.nums(&mut a.bounds)?;
    io.hex(&mut a.colour)?;
    io.nums(&mut a.shader_vars)?;
    io.f32(&mut a.rotation_angle)?;
    io.nums(&mut a.image_index)?;
    io.i32(&mut a.interpolation_time)?;
    io.i32(&mut a.interpolation_property_mask)?;
    io.f32(&mut a.easing_weight)?;
    io.str(&mut a.easing_curve)?;
    io.list(&mut a.triggers, |io, t| {
        io.uid(&mut t.uid)?;
        io.str(&mut t.animation)?;
        io.str(&mut t.state)?;
        io.str(&mut t.property)
    })?;
    io.hex(&mut a.movement_absolute)
}

fn tail<I: Io>(io: &mut I, v: u32, t: &mut Tail) -> Result<()> {
    io.hex(&mut t.b0)?;
    io.str(&mut t.kind)?;
    let has_type = matches!(t.kind.as_str(), "List" | "HorizontalList" | "RadialList" | "Table");
    match t.kind.as_str() {
        "List" | "HorizontalList" => list_engine(io, v, t.list.get_or_insert_with(Default::default))?,
        "RadialList" => {
            let r = t.radial.get_or_insert_with(Default::default);
            io.nums(&mut r.values)?;
            io.hex(&mut r.b)?;
        }
        "Table" => {
            let tb = t.table.get_or_insert_with(Default::default);
            io.list(&mut tb.rows, |io, row| {
                io.list(row, |io, c| {
                    io.f32(&mut c.a)?;
                    io.f32(&mut c.b)?;
                    io.hex(&mut c.rest)
                })
            })?;
            io.hex(&mut tb.end)?;
        }
        _ => {}
    }
    io.str(&mut t.s)?;
    io.flagged(&mut t.ids, |io, ids| io.list(ids, |io, h| io.hex(h)))?;
    if v == 97 && !has_type {
        io.flagged(&mut t.v97, |io, b| {
            io.i32(&mut b.a)?;
            io.i32(&mut b.n)?;
            io.var(&mut b.blob, b.n.max(0) as usize * 4)
        })?;
        io.hex(&mut t.v97_end)?;
    }
    io.flagged(&mut t.model, |io, m| {
        io.str(&mut m.s)?;
        io.hex(&mut m.head)?;
        io.list(&mut m.models, |io, e| {
            io.str(&mut e.s0)?;
            io.str(&mut e.s1)?;
            io.hex(&mut e.b)?;
            io.list(&mut e.anims, |io, a| {
                io.str(&mut a.s0)?;
                io.str(&mut a.s1)?;
                io.hex(&mut a.b)
            })
        })
    })?;
    io.var(&mut t.end, if v <= 93 { 2 } else { 3 })
}

fn list_engine<I: Io>(io: &mut I, v: u32, l: &mut List) -> Result<()> {
    io.list(&mut l.floats, |io, f| io.f32(f))?;
    io.i32(&mut l.a)?;
    io.i32(&mut l.b)?;
    io.hex(&mut l.flag)?;
    io.i32(&mut l.c)?;
    if v < 97 {
        io.var(&mut l.ext, if v == 96 { 8 } else { 3 })
    } else {
        io.var(&mut l.ext, 6)?;
        io.str(&mut l.ext_str)?;
        io.hex(&mut l.ext_tail)
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Names instead of ids, for the text form
// ---------------------------------------------------------------------------------------------------------------

/// `path`, or `#index` if the path is empty, not unique among the images, or looks like an id.
fn image_labels(images: &[Image]) -> Vec<String> {
    let mut counts: HashMap<&str, usize> = HashMap::new();
    images.iter().for_each(|i| *counts.entry(&i.path).or_default() += 1);
    images.iter().enumerate().map(|(n, i)| if !i.path.is_empty() && counts[i.path.as_str()] == 1 && !is_hex8(&i.path) { i.path.clone() } else { format!("#{}", n) }).collect()
}

/// Name -> uid of the states of a component, leaving out names that aren't unique or look like an id.
fn state_names(states: &[State]) -> HashMap<[u8; 4], String> {
    let mut counts: HashMap<&str, usize> = HashMap::new();
    states.iter().for_each(|s| *counts.entry(&s.name).or_default() += 1);
    states.iter().filter(|s| counts[s.name.as_str()] == 1 && !is_hex8(&s.name)).map(|s| (s.uid.b, s.name.clone())).collect()
}

fn component_names(u: &Uic, names: &mut HashMap<[u8; 4], String>, counts: &mut HashMap<String, usize>) {
    names.insert(u.uid.b, u.name.clone());
    *counts.entry(u.name.clone()).or_default() += 1;
    u.children.iter().for_each(|c| component_names(c, names, counts));
}

/// Replaces a reference by its name when there is one; otherwise the raw id stays and its target must keep its id.
fn symbolize_ref(r: &mut Uid, names: &HashMap<[u8; 4], String>, keep: &mut HashSet<[u8; 4]>) {
    if r.b == [0; 4] {
        return;
    }
    match names.get(&r.b) {
        Some(name) => r.sym = Some(name.clone()),
        None => {
            keep.insert(r.b);
        }
    }
}

fn symbolize(u: &mut Uic, comps: &HashMap<[u8; 4], String>, keep: &mut HashSet<[u8; 4]>) {
    let states = state_names(&u.states);
    let labels = image_labels(&u.images);
    let images: HashMap<[u8; 4], String> = u.images.iter().zip(labels).map(|(i, l)| (i.uid.b, l)).collect();
    symbolize_ref(&mut u.default_state, &states, keep);
    symbolize_ref(&mut u.mask_image, &images, keep);
    for s in &mut u.states {
        s.image_metrics.iter_mut().for_each(|m| symbolize_ref(&mut m.image_uid, &images, keep));
        s.mouse.iter_mut().for_each(|m| symbolize_ref(&mut m.state_uid, &states, keep));
    }
    for t in u.funcs.iter_mut().flat_map(|f| f.anims.iter_mut()).flat_map(|a| a.triggers.iter_mut()) {
        symbolize_ref(&mut t.uid, comps, keep);
    }
    u.children.iter_mut().for_each(|c| symbolize(c, comps, keep));
}

fn drop_uids(u: &mut Uic, keep: &HashSet<[u8; 4]>) {
    let clear = |uid: &mut Uid| {
        if !keep.contains(&uid.b) {
            uid.b = [0; 4];
        }
    };
    clear(&mut u.uid);
    u.images.iter_mut().for_each(|i| clear(&mut i.uid));
    u.states.iter_mut().for_each(|s| clear(&mut s.uid));
    u.children.iter_mut().for_each(|c| drop_uids(c, keep));
}

fn fnv32(s: &str) -> u32 {
    s.bytes().fold(0x811c9dc5, |h, b| (h ^ b as u32).wrapping_mul(0x01000193))
}

fn fresh(key: &str, used: &mut HashSet<[u8; 4]>) -> [u8; 4] {
    let mut n = fnv32(key);
    loop {
        let b = n.to_le_bytes();
        if n != 0 && used.insert(b) {
            return b;
        }
        n = n.wrapping_add(1);
    }
}

fn used_uids(u: &Uic, used: &mut HashSet<[u8; 4]>) {
    used.insert(u.uid.b);
    u.images.iter().for_each(|i| {
        used.insert(i.uid.b);
    });
    u.states.iter().for_each(|s| {
        used.insert(s.uid.b);
    });
    u.children.iter().for_each(|c| used_uids(c, used));
}

/// Gives the components, images and states without an id one (derived from where they are, so the same text always
/// gives the same file).
fn generate_uids(u: &mut Uic, path: &str, used: &mut HashSet<[u8; 4]>) {
    if u.uid.b == [0; 4] && u.uid.sym.is_none() {
        u.uid.b = fresh(&format!("{}#component", path), used);
    }
    for (n, i) in u.images.iter_mut().enumerate() {
        if i.uid.b == [0; 4] && i.uid.sym.is_none() {
            i.uid.b = fresh(&format!("{}#image{}", path, n), used);
        }
    }
    for (n, s) in u.states.iter_mut().enumerate() {
        if s.uid.b == [0; 4] && s.uid.sym.is_none() {
            s.uid.b = fresh(&format!("{}#state{}", path, n), used);
        }
    }
    for (n, c) in u.children.iter_mut().enumerate() {
        let child_path = format!("{}/{}[{}]", path, c.name, n);
        generate_uids(c, &child_path, used);
    }
}

fn resolve_ref(r: &mut Uid, names: &HashMap<String, [u8; 4]>, what: &str, path: &str) -> Result<()> {
    if let Some(sym) = r.sym.take() {
        r.b = *names.get(&sym).ok_or_else(|| anyhow!("{}: no {} named {:?}", path, what, sym))?;
    }
    Ok(())
}

fn resolve_names(u: &mut Uic, comps: &HashMap<String, [u8; 4]>, path: &str) -> Result<()> {
    let path = format!("{}/{}", path, u.name);
    let states: HashMap<String, [u8; 4]> = u.states.iter().map(|s| (s.name.clone(), s.uid.b)).collect();
    let mut images: HashMap<String, [u8; 4]> = u.images.iter().enumerate().map(|(n, i)| (format!("#{}", n), i.uid.b)).collect();
    images.extend(image_labels(&u.images).into_iter().zip(u.images.iter().map(|i| i.uid.b)));
    resolve_ref(&mut u.default_state, &states, "state", &path)?;
    resolve_ref(&mut u.mask_image, &images, "image", &path)?;
    for s in &mut u.states {
        for m in &mut s.image_metrics {
            resolve_ref(&mut m.image_uid, &images, "image", &path)?;
        }
        for m in &mut s.mouse {
            resolve_ref(&mut m.state_uid, &states, "state", &path)?;
        }
    }
    for t in u.funcs.iter_mut().flat_map(|f| f.anims.iter_mut()).flat_map(|a| a.triggers.iter_mut()) {
        resolve_ref(&mut t.uid, comps, "component", &path)?;
    }
    u.children.iter_mut().try_for_each(|c| resolve_names(c, comps, &path))
}

fn component_uids(u: &Uic, all: &mut HashMap<String, Vec<[u8; 4]>>) {
    all.entry(u.name.clone()).or_default().push(u.uid.b);
    u.children.iter().for_each(|c| component_uids(c, all));
}

// ---------------------------------------------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------------------------------------------

/// Whether the bytes start with `Version0NN`.
pub fn looks_like_layout(data: &[u8]) -> bool {
    data.len() >= 10 && data.starts_with(b"Version") && data[7..10].iter().all(u8::is_ascii_digit)
}

pub fn decode(data: &[u8]) -> Result<Layout> {
    if !looks_like_layout(data) {
        bail!("not a layout file (no `Version0NN` header)");
    }
    let version: u32 = std::str::from_utf8(&data[7..10])?.parse()?;
    if !(MIN_VERSION..=MAX_VERSION).contains(&version) {
        bail!("layout version {} is not supported (Attila: {} to {})", version, MIN_VERSION, MAX_VERSION);
    }
    let mut r = Reader { data, pos: 10 };
    let mut root = Uic::default();
    uic(&mut r, version, &mut root)?;
    if r.pos() != data.len() {
        bail!("{} bytes left over after the root component (at {:#x})", data.len() - r.pos(), r.pos());
    }
    Ok(Layout { version, root })
}

pub fn encode(layout: &Layout) -> Result<Vec<u8>> {
    if !(MIN_VERSION..=MAX_VERSION).contains(&layout.version) {
        bail!("layout version {} is not supported (Attila: {} to {})", layout.version, MIN_VERSION, MAX_VERSION);
    }
    let mut w = Writer(format!("Version{:03}", layout.version).into_bytes());
    let mut root = layout.root.clone();
    uic(&mut w, layout.version, &mut root)?;
    Ok(w.0)
}

/// The layout as YAML. `keep_uids: false` leaves out the ids of components, images and states that nothing refers to
/// by raw id: shorter to read, and `from_text` makes new ones.
pub fn to_text(layout: &Layout, keep_uids: bool) -> Result<String> {
    let mut layout = layout.clone();
    let mut comps = HashMap::new();
    let mut counts = HashMap::new();
    component_names(&layout.root, &mut comps, &mut counts);
    // A trigger can only name a component whose name is unique.
    comps.retain(|_, name| counts[name.as_str()] == 1 && !is_hex8(name));
    let mut keep = HashSet::new();
    symbolize(&mut layout.root, &comps, &mut keep);
    if !keep_uids {
        drop_uids(&mut layout.root, &keep);
    }
    Ok(serde_yaml_ng::to_string(&layout)?)
}

pub fn from_text(text: &str) -> Result<Layout> {
    let mut layout: Layout = serde_yaml_ng::from_str(text)?;
    let mut used = HashSet::new();
    used_uids(&layout.root, &mut used);
    generate_uids(&mut layout.root, "", &mut used);
    let mut all = HashMap::new();
    component_uids(&layout.root, &mut all);
    let comps: HashMap<String, [u8; 4]> = all.into_iter().filter(|(_, uids)| uids.len() == 1).map(|(name, uids)| (name, uids[0])).collect();
    resolve_names(&mut layout.root, &comps, "")?;
    Ok(layout)
}
