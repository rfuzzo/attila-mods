// ESF files (startpos.esf, saves, map data): an indented text tree to read and grep them, a CAAB writer, and the
// slot edit for `docs/BUG-missing-building-slots.md`.
//
// A record prints as `NAME` with its children indented below; a record with several blocks (a list of entries, e.g.
// one per region) prints each block as `NAME[i]`. Leaves print as `type value`, arrays on one line.
//
// Decoding is rpfm_lib's. Its CAAB writer (v5.1.1) writes a `utf16[]` array's length as a u32 where its reader
// expects a CAULEB128, like for every other array, so its output doesn't decode again. `encode_caab` is a port of it
// with that fixed, and keeps the original string tables' order, so an unchanged file comes back byte-identical.
//
// A startpos is two ESFs: the outer one has SAVE_GAME_HEADER, CAMPAIGN_PREOPEN_MAP_INFO and COMPRESSED_DATA, which
// holds the whole campaign (BUILD, the same header and map info, CAMPAIGN_ENV) as an LZMA1-compressed ESF.
// rpfm_lib's decoder silently returns that inner ESF in place of the outer one; `Startpos` keeps both.

use std::collections::HashMap;
use std::fmt::Write;

use anyhow::{anyhow, bail, Context, Result};
use rpfm_lib::binary::{ReadBytes, WriteBytes};
use rpfm_lib::compression::Decompressible;
use rpfm_lib::files::esf::{NodeType, RecordNode, RecordNodeFlags, ESF};
use rpfm_lib::files::Decodeable;

/// Decodes with rpfm_lib (a startpos comes back as its inner ESF).
pub fn decode(data: &[u8]) -> Result<ESF> {
    ESF::decode(&mut std::io::Cursor::new(data), &None).context("decoding ESF")
}

pub fn dump(esf: &ESF) -> String {
    let mut out = String::new();
    node(&mut out, esf.root_node(), 0);
    out
}

fn node(out: &mut String, node: &NodeType, depth: usize) {
    let indent = "  ".repeat(depth);
    match node {
        NodeType::Record(record) => {
            let blocks = record.children();
            if blocks.len() == 1 {
                let _ = writeln!(out, "{}{}", indent, record.name());
                for child in &blocks[0] {
                    self::node(out, child, depth + 1);
                }
            } else {
                let _ = writeln!(out, "{}{} ({} blocks)", indent, record.name(), blocks.len());
                for (i, block) in blocks.iter().enumerate() {
                    let _ = writeln!(out, "{}  {}[{}]", indent, record.name(), i);
                    for child in block {
                        self::node(out, child, depth + 2);
                    }
                }
            }
        }
        leaf => {
            let _ = writeln!(out, "{}{}", indent, leaf_text(leaf));
        }
    }
}

fn leaf_text(node: &NodeType) -> String {
    match node {
        NodeType::Bool(n) => format!("bool {}", n.value()),
        NodeType::I8(v) => format!("i8 {}", v),
        NodeType::I16(v) => format!("i16 {}", v),
        NodeType::I32(n) => format!("i32 {}", n.value()),
        NodeType::I64(v) => format!("i64 {}", v),
        NodeType::U8(v) => format!("u8 {}", v),
        NodeType::U16(v) => format!("u16 {}", v),
        NodeType::U32(n) => format!("u32 {}", n.value()),
        NodeType::U64(v) => format!("u64 {}", v),
        NodeType::F32(n) => format!("f32 {}", n.value()),
        NodeType::F64(v) => format!("f64 {}", v),
        NodeType::Coord2d(c) => format!("coord2d {} {}", c.x(), c.y()),
        NodeType::Coord3d(c) => format!("coord3d {} {} {}", c.x(), c.y(), c.z()),
        NodeType::Utf16(s) => format!("utf16 {:?}", s),
        NodeType::Ascii(s) => format!("ascii {:?}", s),
        NodeType::Angle(v) => format!("angle {}", v),
        NodeType::BoolArray(v) => format!("bool[] {:?}", v),
        NodeType::I8Array(v) => format!("i8[] {:?}", v),
        NodeType::I16Array(v) => format!("i16[] {:?}", v),
        NodeType::I32Array(n) => format!("i32[] {:?}", n.value()),
        NodeType::I64Array(v) => format!("i64[] {:?}", v),
        NodeType::U8Array(v) => format!("u8[] {:?}", v),
        NodeType::U16Array(v) => format!("u16[] {:?}", v),
        NodeType::U32Array(n) => format!("u32[] {:?}", n.value()),
        NodeType::U64Array(v) => format!("u64[] {:?}", v),
        NodeType::F32Array(v) => format!("f32[] {:?}", v),
        NodeType::F64Array(v) => format!("f64[] {:?}", v),
        NodeType::Utf16Array(v) => format!("utf16[] {:?}", v),
        NodeType::AsciiArray(v) => format!("ascii[] {:?}", v),
        NodeType::AngleArray(v) => format!("angle[] {:?}", v),
        other => format!("{:?}", other),
    }
}

//---------------------------------------------------------------------------//
// CAAB writer
//---------------------------------------------------------------------------//

/// The string tables at the end of a CAAB file, in file order.
#[derive(Clone, Default)]
pub struct Strings {
    names: Vec<String>,
    utf16: Vec<(String, u32)>,
    utf8: Vec<(String, u32)>,
}

impl Strings {
    pub fn parse(data: &[u8]) -> Result<Self> {
        if data.get(..4) != Some(&[0xCA, 0xAB, 0, 0][..]) {
            bail!("not a CAAB ESF");
        }
        let mut c = std::io::Cursor::new(data);
        c.set_position(u32::from_le_bytes(data[12..16].try_into()?) as u64);
        let mut strings = Self::default();
        for _ in 0..c.read_u16()? {
            strings.names.push(c.read_sized_string_u8()?);
        }
        for _ in 0..c.read_u32()? {
            let text = c.read_sized_string_u16()?;
            strings.utf16.push((text, c.read_u32()?));
        }
        for _ in 0..c.read_u32()? {
            let text = c.read_sized_string_u8()?;
            strings.utf8.push((text, c.read_u32()?));
        }
        Ok(strings)
    }
}

/// The tables to write: the original ones, plus the strings the tree has and they don't, at the end.
struct Tables {
    strings: Strings,
    names: HashMap<String, u16>,
    utf16: HashMap<String, u32>,
    utf8: HashMap<String, u32>,
}

impl Tables {
    fn new(base: &Strings, root: &NodeType) -> Self {
        let mut t = Tables { strings: Strings::default(), names: HashMap::new(), utf16: HashMap::new(), utf8: HashMap::new() };
        base.names.iter().for_each(|n| t.add_name(n));
        for (text, index) in &base.utf16 {
            t.utf16.entry(text.clone()).or_insert(*index);
            t.strings.utf16.push((text.clone(), *index));
        }
        for (text, index) in &base.utf8 {
            t.utf8.entry(text.clone()).or_insert(*index);
            t.strings.utf8.push((text.clone(), *index));
        }
        t.collect(root);
        t
    }

    fn add_name(&mut self, name: &str) {
        if !self.names.contains_key(name) {
            self.names.insert(name.to_owned(), self.strings.names.len() as u16);
            self.strings.names.push(name.to_owned());
        }
    }

    fn add_string(map: &mut HashMap<String, u32>, list: &mut Vec<(String, u32)>, text: &str) {
        if !map.contains_key(text) {
            let index = list.iter().map(|(_, i)| i + 1).max().unwrap_or(0);
            map.insert(text.to_owned(), index);
            list.push((text.to_owned(), index));
        }
    }

    fn collect(&mut self, node: &NodeType) {
        match node {
            NodeType::Utf16(v) => Self::add_string(&mut self.utf16, &mut self.strings.utf16, v),
            NodeType::Ascii(v) => Self::add_string(&mut self.utf8, &mut self.strings.utf8, v),
            NodeType::Utf16Array(v) => v.iter().for_each(|v| Self::add_string(&mut self.utf16, &mut self.strings.utf16, v)),
            NodeType::AsciiArray(v) => v.iter().for_each(|v| Self::add_string(&mut self.utf8, &mut self.strings.utf8, v)),
            NodeType::Record(r) => {
                self.add_name(r.name());
                r.children().iter().flatten().for_each(|n| self.collect(n));
            }
            _ => {}
        }
    }
}

/// Encodes an ESF as CAAB, keeping the order of `strings` (the original file's tables, or empty).
pub fn encode_caab(esf: &ESF, strings: &Strings) -> Result<Vec<u8>> {
    let tables = Tables::new(strings, esf.root_node());
    let mut nodes = vec![];
    write_node(&mut nodes, esf.root_node(), true, &tables)?;

    let mut out = vec![0xCA, 0xAB, 0, 0];
    out.write_u32(*esf.unknown_1())?;
    out.write_u32(*esf.creation_date())?;
    out.write_u32((16 + nodes.len()) as u32)?;
    out.extend_from_slice(&nodes);
    let s = &tables.strings;
    out.write_u16(s.names.len() as u16)?;
    for name in &s.names {
        out.write_sized_string_u8(name)?;
    }
    out.write_u32(s.utf16.len() as u32)?;
    for (text, index) in &s.utf16 {
        out.write_sized_string_u16(text)?;
        out.write_u32(*index)?;
    }
    out.write_u32(s.utf8.len() as u32)?;
    for (text, index) in &s.utf8 {
        out.write_sized_string_u8(text)?;
        out.write_u32(*index)?;
    }
    Ok(out)
}

// Node type markers (private in rpfm_lib).
const BOOL: u8 = 0x01;
const I8: u8 = 0x02;
const I16: u8 = 0x03;
const I32: u8 = 0x04;
const I64: u8 = 0x05;
const U8: u8 = 0x06;
const U16: u8 = 0x07;
const U32: u8 = 0x08;
const U64: u8 = 0x09;
const F32: u8 = 0x0a;
const F64: u8 = 0x0b;
const COORD_2D: u8 = 0x0c;
const COORD_3D: u8 = 0x0d;
const UTF16: u8 = 0x0e;
const ASCII: u8 = 0x0f;
const ANGLE: u8 = 0x10;
const BOOL_TRUE: u8 = 0x12;
const BOOL_FALSE: u8 = 0x13;
const U32_ZERO: u8 = 0x14;
const U32_ONE: u8 = 0x15;
const U32_BYTE: u8 = 0x16;
const U32_16BIT: u8 = 0x17;
const U32_24BIT: u8 = 0x18;
const I32_ZERO: u8 = 0x19;
const I32_BYTE: u8 = 0x1a;
const I32_16BIT: u8 = 0x1b;
const I32_24BIT: u8 = 0x1c;
const F32_ZERO: u8 = 0x1d;
const UNKNOWN_21: u8 = 0x21;
const UNKNOWN_23: u8 = 0x23;
const UNKNOWN_24: u8 = 0x24;
const UNKNOWN_25: u8 = 0x25;
const UNKNOWN_26: u8 = 0x26;
const BOOL_ARRAY: u8 = 0x41;
const I8_ARRAY: u8 = 0x42;
const I16_ARRAY: u8 = 0x43;
const I32_ARRAY: u8 = 0x44;
const I64_ARRAY: u8 = 0x45;
const U8_ARRAY: u8 = 0x46;
const U16_ARRAY: u8 = 0x47;
const U32_ARRAY: u8 = 0x48;
const U64_ARRAY: u8 = 0x49;
const F32_ARRAY: u8 = 0x4a;
const F64_ARRAY: u8 = 0x4b;
const COORD_2D_ARRAY: u8 = 0x4c;
const COORD_3D_ARRAY: u8 = 0x4d;
const UTF16_ARRAY: u8 = 0x4e;
const ASCII_ARRAY: u8 = 0x4f;
const ANGLE_ARRAY: u8 = 0x50;
const U32_BYTE_ARRAY: u8 = 0x56;
const U32_16BIT_ARRAY: u8 = 0x57;
const U32_24BIT_ARRAY: u8 = 0x58;
const I32_BYTE_ARRAY: u8 = 0x5a;
const I32_16BIT_ARRAY: u8 = 0x5b;
const I32_24BIT_ARRAY: u8 = 0x5c;

fn sized(out: &mut Vec<u8>, marker: u8, list: &[u8]) -> Result<()> {
    out.write_u8(marker)?;
    out.write_cauleb128(list.len() as u32, 0)?;
    out.extend_from_slice(list);
    Ok(())
}

fn le<T: Copy, const N: usize>(values: &[T], bytes: impl Fn(T) -> [u8; N]) -> Vec<u8> {
    values.iter().flat_map(|&v| bytes(v)).collect()
}

/// rpfm_lib's `save_node`, with the `utf16[]` length fixed and strings looked up in `t`.
fn write_node(out: &mut Vec<u8>, node: &NodeType, is_root: bool, t: &Tables) -> Result<()> {
    match node {
        NodeType::Invalid => bail!("invalid node"),
        NodeType::Bool(n) => match (*n.optimized(), *n.value()) {
            (true, true) => out.write_u8(BOOL_TRUE)?,
            (true, false) => out.write_u8(BOOL_FALSE)?,
            (false, v) => {
                out.write_u8(BOOL)?;
                out.write_bool(v)?;
            }
        },
        NodeType::I8(v) => {
            out.write_u8(I8)?;
            out.write_i8(*v)?;
        }
        NodeType::I16(v) => {
            out.write_u8(I16)?;
            out.write_i16(*v)?;
        }
        NodeType::I32(n) => {
            let v = *n.value();
            if !*n.optimized() {
                out.write_u8(I32)?;
                out.write_i32(v)?;
            } else if v == 0 {
                out.write_u8(I32_ZERO)?;
            } else if (i8::MIN as i32..=i8::MAX as i32).contains(&v) {
                out.write_u8(I32_BYTE)?;
                out.write_i8(v as i8)?;
            } else if (i16::MIN as i32..=i16::MAX as i32).contains(&v) {
                out.write_u8(I32_16BIT)?;
                out.write_i16(v as i16)?;
            } else if (-8_388_608..=8_388_607).contains(&v) {
                out.write_u8(I32_24BIT)?;
                out.write_i24(v)?;
            } else {
                out.write_u8(I32)?;
                out.write_i32(v)?;
            }
        }
        NodeType::I64(v) => {
            out.write_u8(I64)?;
            out.write_i64(*v)?;
        }
        NodeType::U8(v) => {
            out.write_u8(U8)?;
            out.write_u8(*v)?;
        }
        NodeType::U16(v) => {
            out.write_u8(U16)?;
            out.write_u16(*v)?;
        }
        NodeType::U32(n) => {
            let v = *n.value();
            if !*n.optimized() {
                out.write_u8(U32)?;
                out.write_u32(v)?;
            } else if v == 0 {
                out.write_u8(U32_ZERO)?;
            } else if v == 1 {
                out.write_u8(U32_ONE)?;
            } else if v <= 0xFF {
                out.write_u8(U32_BYTE)?;
                out.write_u8(v as u8)?;
            } else if v <= 0xFFFF {
                out.write_u8(U32_16BIT)?;
                out.write_u16(v as u16)?;
            } else if v <= 0xFF_FFFF {
                out.write_u8(U32_24BIT)?;
                out.write_u24(v)?;
            } else {
                out.write_u8(U32)?;
                out.write_u32(v)?;
            }
        }
        NodeType::U64(v) => {
            out.write_u8(U64)?;
            out.write_u64(*v)?;
        }
        NodeType::F32(n) => {
            if *n.optimized() && (*n.value() - 0.0).abs() < f32::EPSILON {
                out.write_u8(F32_ZERO)?;
            } else {
                out.write_u8(F32)?;
                out.write_f32(*n.value())?;
            }
        }
        NodeType::F64(v) => {
            out.write_u8(F64)?;
            out.write_f64(*v)?;
        }
        NodeType::Coord2d(c) => {
            out.write_u8(COORD_2D)?;
            out.write_f32(*c.x())?;
            out.write_f32(*c.y())?;
        }
        NodeType::Coord3d(c) => {
            out.write_u8(COORD_3D)?;
            out.write_f32(*c.x())?;
            out.write_f32(*c.y())?;
            out.write_f32(*c.z())?;
        }
        NodeType::Utf16(v) => {
            out.write_u8(UTF16)?;
            out.write_u32(t.utf16[v])?;
        }
        NodeType::Ascii(v) => {
            out.write_u8(ASCII)?;
            out.write_u32(t.utf8[v])?;
        }
        NodeType::Angle(v) => {
            out.write_u8(ANGLE)?;
            out.write_i16(*v)?;
        }
        NodeType::Unknown21(v) => {
            out.write_u8(UNKNOWN_21)?;
            out.write_u32(*v)?;
        }
        NodeType::Unknown23(v) => {
            out.write_u8(UNKNOWN_23)?;
            out.write_u8(*v)?;
        }
        NodeType::Unknown24(v) => {
            out.write_u8(UNKNOWN_24)?;
            out.write_u16(*v)?;
        }
        NodeType::Unknown25(v) => {
            out.write_u8(UNKNOWN_25)?;
            out.write_u32(*v)?;
        }
        NodeType::Unknown26(v) => {
            out.write_u8(UNKNOWN_26)?;
            out.extend_from_slice(v);
        }
        NodeType::BoolArray(v) => sized(out, BOOL_ARRAY, &v.iter().map(|&b| b as u8).collect::<Vec<_>>())?,
        NodeType::I8Array(v) => sized(out, I8_ARRAY, v)?,
        NodeType::I16Array(v) => sized(out, I16_ARRAY, &le(v, i16::to_le_bytes))?,
        NodeType::I32Array(n) => {
            let v = n.value();
            let max = v.iter().max().map(|max| max.abs().max(v.iter().min().unwrap().abs()));
            let (marker, width) = match max {
                Some(m) if *n.optimized() && m <= i8::MAX as i32 => (I32_BYTE_ARRAY, 1),
                Some(m) if *n.optimized() && m <= i16::MAX as i32 => (I32_16BIT_ARRAY, 2),
                Some(m) if *n.optimized() && m <= 8_388_607 => (I32_24BIT_ARRAY, 3),
                // rpfm_lib writes no marker at all for an empty optimized array; I32_ARRAY is what it reads back as.
                _ => (I32_ARRAY, 4),
            };
            sized(out, marker, &v.iter().flat_map(|x| x.to_le_bytes()[..width].to_vec()).collect::<Vec<_>>())?;
        }
        NodeType::I64Array(v) => sized(out, I64_ARRAY, &le(v, i64::to_le_bytes))?,
        NodeType::U8Array(v) => sized(out, U8_ARRAY, v)?,
        NodeType::U16Array(v) => sized(out, U16_ARRAY, &le(v, u16::to_le_bytes))?,
        NodeType::U32Array(n) => {
            let v = n.value();
            let (marker, width) = match v.iter().max() {
                Some(&m) if *n.optimized() && m < 0xFF => (U32_BYTE_ARRAY, 1),
                Some(&m) if *n.optimized() && m < 0xFFFF => (U32_16BIT_ARRAY, 2),
                Some(&m) if *n.optimized() && m < 0xFF_FFFF => (U32_24BIT_ARRAY, 3),
                _ => (U32_ARRAY, 4),
            };
            sized(out, marker, &v.iter().flat_map(|x| x.to_le_bytes()[..width].to_vec()).collect::<Vec<_>>())?;
        }
        NodeType::U64Array(v) => sized(out, U64_ARRAY, &le(v, u64::to_le_bytes))?,
        NodeType::F32Array(v) => sized(out, F32_ARRAY, &le(v, f32::to_le_bytes))?,
        NodeType::F64Array(v) => sized(out, F64_ARRAY, &le(v, f64::to_le_bytes))?,
        NodeType::Coord2dArray(v) => {
            let list: Vec<u8> = v.iter().flat_map(|c| [c.x().to_le_bytes(), c.y().to_le_bytes()].concat()).collect();
            sized(out, COORD_2D_ARRAY, &list)?;
        }
        NodeType::Coord3dArray(v) => {
            let list: Vec<u8> = v.iter().flat_map(|c| [c.x().to_le_bytes(), c.y().to_le_bytes(), c.z().to_le_bytes()].concat()).collect();
            sized(out, COORD_3D_ARRAY, &list)?;
        }
        NodeType::Utf16Array(v) => sized(out, UTF16_ARRAY, &v.iter().flat_map(|x| t.utf16[x].to_le_bytes()).collect::<Vec<_>>())?,
        NodeType::AsciiArray(v) => sized(out, ASCII_ARRAY, &v.iter().flat_map(|x| t.utf8[x].to_le_bytes()).collect::<Vec<_>>())?,
        NodeType::AngleArray(v) => sized(out, ANGLE_ARRAY, &le(v, i16::to_le_bytes))?,
        NodeType::Record(r) => {
            let name = t.names[r.name()];
            let flags = *r.record_flags();
            if flags.contains(RecordNodeFlags::HAS_NON_OPTIMIZED_INFO) || is_root {
                out.write_u8(flags.bits())?;
                out.write_u16(name)?;
                out.write_u8(*r.version())?;
            } else {
                let info: u16 = ((flags.bits() as u16) << 8) | ((*r.version() as u16) << 9) | name;
                out.write_u16(info.swap_bytes())?;
            }
            let mut children = vec![];
            if flags.contains(RecordNodeFlags::HAS_NESTED_BLOCKS) {
                for block in r.children() {
                    let mut data = vec![];
                    for child in block {
                        write_node(&mut data, child, false, t)?;
                    }
                    children.write_cauleb128(data.len() as u32, 0)?;
                    children.extend_from_slice(&data);
                }
                out.write_cauleb128(children.len() as u32, 0)?;
                out.write_cauleb128(r.children().len() as u32, 0)?;
            } else {
                for child in r.children().first().into_iter().flatten() {
                    write_node(&mut children, child, false, t)?;
                }
                out.write_cauleb128(children.len() as u32, 0)?;
            }
            out.extend_from_slice(&children);
        }
    }
    Ok(())
}

//---------------------------------------------------------------------------//
// Startpos: outer ESF + compressed inner ESF
//---------------------------------------------------------------------------//

const COMPRESSED_DATA: &str = "COMPRESSED_DATA";
const COMPRESSED_DATA_HIDDEN: &str = "COMPRESSED_DATX";

/// An ESF as stored. For a startpos (or anything with a `COMPRESSED_DATA` record last in the root), `inner` is the
/// compressed ESF and `outer` the file around it; otherwise `outer` is the file and `inner` is None.
pub struct Stored {
    pub outer: ESF,
    outer_strings: Strings,
    pub inner: Option<(ESF, Strings)>,
    /// The decompressed inner ESF as read, to check the writer against.
    pub inner_bytes: Option<Vec<u8>>,
}

impl Stored {
    pub fn read(data: &[u8]) -> Result<Self> {
        let outer = decode_outer(data)?;
        let outer_strings = Strings::parse(data)?;
        let inner_bytes = compressed_payload(&outer)?;
        let inner = match &inner_bytes {
            Some(bytes) => Some((decode(bytes)?, Strings::parse(bytes)?)),
            None => None,
        };
        Ok(Stored { outer, outer_strings, inner, inner_bytes })
    }

    /// The ESF with the campaign in it.
    pub fn campaign_mut(&mut self) -> &mut ESF {
        match &mut self.inner {
            Some((esf, _)) => esf,
            None => &mut self.outer,
        }
    }

    /// Encodes the inner ESF, compresses it into the outer one, and encodes that.
    pub fn write(&self) -> Result<Vec<u8>> {
        let mut outer = self.outer.clone();
        if let Some((inner, strings)) = &self.inner {
            set_compressed_payload(&mut outer, &encode_caab(inner, strings)?)?;
        }
        encode_caab(&outer, &self.outer_strings)
    }

    /// Re-encodes without changes: the outer file with its original compressed payload, and the inner ESF.
    pub fn check(&self, original: &[u8]) -> Result<Vec<String>> {
        let mut report = vec![compare("file", &encode_caab(&self.outer, &self.outer_strings)?, original)];
        if let (Some((inner, strings)), Some(bytes)) = (&self.inner, &self.inner_bytes) {
            report.push(compare("compressed ESF", &encode_caab(inner, strings)?, bytes));
            let rewritten = self.write()?;
            let again = Stored::read(&rewritten)?;
            let same = again.inner.as_ref().map(|(e, _)| e) == Some(inner) && again.outer.root_node() != &NodeType::Invalid;
            report.push(format!("recompressed file: {} bytes, {}", rewritten.len(), if same { "reads back as the same campaign" } else { "reads back DIFFERENT" }));
        }
        Ok(report)
    }
}

fn compare(what: &str, encoded: &[u8], original: &[u8]) -> String {
    match encoded.iter().zip(original).position(|(a, b)| a != b) {
        None if encoded.len() == original.len() => format!("{}: identical ({} bytes)", what, original.len()),
        None => format!("{}: same up to byte {}, then the lengths differ ({} encoded, {} original)", what, encoded.len().min(original.len()), encoded.len(), original.len()),
        Some(at) => format!("{}: differs at byte {:#x} ({} encoded, {} original)", what, at, encoded.len(), original.len()),
    }
}

/// Decodes without rpfm_lib's swap to the compressed ESF: hides `COMPRESSED_DATA` in a copy's record-name table
/// (same length, so nothing moves), and renames the record back afterwards.
fn decode_outer(data: &[u8]) -> Result<ESF> {
    let mut copy = data.to_vec();
    let offset = u32::from_le_bytes(data.get(12..16).ok_or_else(|| anyhow!("too short"))?.try_into()?) as usize;
    let count = u16::from_le_bytes(data[offset..offset + 2].try_into()?);
    let mut p = offset + 2;
    for _ in 0..count {
        let len = u16::from_le_bytes(copy[p..p + 2].try_into()?) as usize;
        if &copy[p + 2..p + 2 + len] == COMPRESSED_DATA.as_bytes() {
            copy[p + 2..p + 2 + len].copy_from_slice(COMPRESSED_DATA_HIDDEN.as_bytes());
        }
        p += 2 + len;
    }
    let mut esf = decode(&copy)?;
    let mut root = esf.root_node().clone();
    if let NodeType::Record(r) = &mut root {
        for child in r.children_mut().iter_mut().flatten() {
            if let NodeType::Record(c) = child {
                if c.name() == COMPRESSED_DATA_HIDDEN {
                    c.set_name(COMPRESSED_DATA.to_owned());
                }
            }
        }
    }
    esf.set_root_node(root);
    Ok(esf)
}

fn compressed_record(root: &NodeType) -> Option<&RecordNode> {
    match root {
        NodeType::Record(r) => r.children().first()?.iter().find_map(|c| match c {
            NodeType::Record(c) if c.name() == COMPRESSED_DATA => Some(&**c),
            _ => None,
        }),
        _ => None,
    }
}

/// The decompressed ESF in `COMPRESSED_DATA { u8[] data, COMPRESSED_DATA_INFO { u32 size, u8[] lzma properties } }`.
fn compressed_payload(outer: &ESF) -> Result<Option<Vec<u8>>> {
    let Some(record) = compressed_record(outer.root_node()) else { return Ok(None) };
    let children = &record.children()[0];
    let (Some(NodeType::U8Array(data)), Some(NodeType::Record(info))) = (children.first(), children.get(1)) else {
        bail!("unexpected COMPRESSED_DATA layout");
    };
    let (Some(NodeType::U32(size)), Some(NodeType::U8Array(props))) = (info.children()[0].first(), info.children()[0].get(1)) else {
        bail!("unexpected COMPRESSED_DATA_INFO layout");
    };
    let mut lzma = vec![];
    lzma.write_u32(*size.value())?;
    lzma.extend_from_slice(props);
    lzma.extend_from_slice(data);
    Ok(Some(lzma.as_slice().decompress().context("decompressing COMPRESSED_DATA")?))
}

/// LZMA1 the way CA's startposes have it (properties `5d 00 00 40 00`: lc 3, lp 0, pb 2, 4 MB dictionary).
/// rpfm_lib's compressor (lzma-rs) only writes literals, which makes a startpos 2.5 times as big.
fn lzma1(data: &[u8]) -> Result<(Vec<u8>, Vec<u8>)> {
    use std::io::Write as _;
    let mut options = xz2::stream::LzmaOptions::new_preset(9)?;
    options.dict_size(4 << 20).literal_context_bits(3).literal_position_bits(0).position_bits(2);
    let stream = xz2::stream::Stream::new_lzma_encoder(&options)?;
    let mut encoder = xz2::write::XzEncoder::new_stream(Vec::new(), stream);
    encoder.write_all(data)?;
    // .lzma: 5 bytes of properties, u64 size (unknown, so the stream ends with an end marker), the stream.
    let mut alone = encoder.finish()?;
    let stream = alone.split_off(13);
    alone.truncate(5);
    Ok((alone, stream))
}

fn set_compressed_payload(outer: &mut ESF, inner: &[u8]) -> Result<()> {
    let (props, data) = lzma1(inner)?;
    let size = inner.len() as u32;

    let mut root = outer.root_node().clone();
    let NodeType::Record(r) = &mut root else { bail!("root isn't a record") };
    let record = r
        .children_mut()
        .iter_mut()
        .flatten()
        .find_map(|c| match c {
            NodeType::Record(c) if c.name() == COMPRESSED_DATA => Some(c),
            _ => None,
        })
        .ok_or_else(|| anyhow!("no COMPRESSED_DATA"))?;
    let children = &mut record.children_mut()[0];
    children[0] = NodeType::U8Array(data);
    let NodeType::Record(info) = &mut children[1] else { bail!("no COMPRESSED_DATA_INFO") };
    let info = &mut info.children_mut()[0];
    let NodeType::U32(n) = &mut info[0] else { bail!("no size in COMPRESSED_DATA_INFO") };
    *n.value_mut() = size;
    info[1] = NodeType::U8Array(props);
    outer.set_root_node(root);
    Ok(())
}

//---------------------------------------------------------------------------//
// Adding building slots
//---------------------------------------------------------------------------//

fn first_u32(r: &RecordNode) -> Option<u32> {
    match r.children().first()?.first()? {
        NodeType::U32(n) => Some(*n.value()),
        _ => None,
    }
}

fn child_record<'a>(r: &'a RecordNode, name: &str) -> Option<&'a RecordNode> {
    r.children().iter().flatten().find_map(|c| match c {
        NodeType::Record(c) if c.name() == name => Some(&**c),
        _ => None,
    })
}

/// What the slot edit needs from the whole file: the highest slot and garrison ids, and an empty building manager.
#[derive(Default)]
struct SlotScan {
    max_slot: u32,
    max_garrison: u32,
    empty_manager: Option<NodeType>,
}

impl SlotScan {
    fn scan(&mut self, node: &NodeType) {
        let NodeType::Record(r) = node else { return };
        match r.name().as_str() {
            "REGION_SLOT" => {
                self.max_slot = self.max_slot.max(first_u32(r).unwrap_or(0));
                if self.empty_manager.is_none() {
                    // An empty slot's manager: `u32 4, bool false, ascii "", ...` with no BUILDING_BASE.
                    if let Some(m) = child_record(r, "REGION_BUILDING_MANAGER") {
                        if matches!(m.children()[0].get(1), Some(NodeType::Bool(b)) if !*b.value()) && child_record(m, "BUILDING_BASE").is_none() {
                            self.empty_manager = Some(NodeType::Record(Box::new(m.clone())));
                        }
                    }
                }
            }
            "GARRISON_RESIDENCE" => self.max_garrison = self.max_garrison.max(first_u32(r).unwrap_or(0)),
            _ => {}
        }
        r.children().iter().flatten().for_each(|c| self.scan(c));
    }
}

fn find_region<'a>(node: &'a mut NodeType, key: &str) -> Option<&'a mut RecordNode> {
    let NodeType::Record(r) = node else { return None };
    let is_region = r.name() == "REGION"
        && matches!(r.children().first().and_then(|c| c.get(1)), Some(NodeType::Ascii(k)) if k == key)
        && child_record(r, "REGION_SLOT_MANAGER").is_some();
    if is_region {
        return Some(&mut **r);
    }
    r.children_mut().iter_mut().flatten().find_map(|c| find_region(c, key))
}

fn slot_strings(slot: &RecordNode) -> Vec<String> {
    slot.children()[0].iter().filter_map(|c| match c {
        NodeType::Ascii(s) => Some(s.clone()),
        _ => None,
    }).collect()
}

/// Adds one empty secondary slot to each region: a copy of its last secondary slot (same template), with the next
/// index in its key, an empty building manager, and new slot and garrison ids after the highest ones in the file.
pub fn add_slots(esf: &mut ESF, regions: &[String]) -> Result<Vec<String>> {
    let mut scan = SlotScan::default();
    scan.scan(esf.root_node());
    let empty_manager = scan.empty_manager.ok_or_else(|| anyhow!("no empty slot to copy a building manager from"))?;
    let mut root = esf.root_node().clone();
    let mut report = vec![];
    for key in regions {
        let region = find_region(&mut root, key).ok_or_else(|| anyhow!("no region {}", key))?;
        let manager = region
            .children_mut()
            .iter_mut()
            .flatten()
            .find_map(|c| match c {
                NodeType::Record(c) if c.name() == "REGION_SLOT_MANAGER" => Some(c),
                _ => None,
            })
            .unwrap();
        let array = manager
            .children_mut()
            .iter_mut()
            .flatten()
            .find_map(|c| match c {
                NodeType::Record(c) if c.name() == "REGION_SLOT_ARRAY" => Some(c),
                _ => None,
            })
            .ok_or_else(|| anyhow!("{}: no REGION_SLOT_ARRAY", key))?;
        let blocks = array.children_mut();
        let index = blocks.len();
        for (i, block) in blocks.iter().enumerate() {
            let Some(NodeType::Record(slot)) = block.first() else { bail!("{}: unexpected slot block", key) };
            if !slot_strings(slot).contains(&format!("{}:{}", key, i)) {
                bail!("{}: slot {} isn't keyed {}:{}", key, i, key, i);
            }
        }
        let template = blocks
            .iter()
            .rev()
            .find(|b| matches!(b.first(), Some(NodeType::Record(s)) if slot_strings(s).iter().any(|x| x == "secondary")))
            .ok_or_else(|| anyhow!("{}: no secondary slot to copy", key))?;
        let mut block = template.clone();
        let Some(NodeType::Record(slot)) = block.first_mut() else { unreachable!() };
        let slot_id = scan.max_slot + 1;
        let garrison_id = scan.max_garrison + 1;
        let new_key = format!("{}:{}", key, index);
        let children = &mut slot.children_mut()[0];
        // REGION_SLOT: u32 id, GARRISON_RESIDENCE, REGION_BUILDING_MANAGER, ascii key, ascii template, ascii type, ...
        let (Some(NodeType::U32(id)), Some(NodeType::Record(garrison)), Some(NodeType::Record(_)), Some(NodeType::Ascii(slot_key))) =
            (children.first(), children.get(1), children.get(2), children.get(3))
        else {
            bail!("{}: unexpected REGION_SLOT layout", key);
        };
        if *id.value() > scan.max_slot || garrison.name() != "GARRISON_RESIDENCE" || !slot_key.starts_with(&format!("{}:", key)) {
            bail!("{}: unexpected REGION_SLOT layout", key);
        }
        if let NodeType::U32(id) = &mut children[0] {
            *id.value_mut() = slot_id;
        }
        if let NodeType::Record(garrison) = &mut children[1] {
            let NodeType::U32(n) = &mut garrison.children_mut()[0][0] else { bail!("{}: garrison without id", key) };
            *n.value_mut() = garrison_id;
        }
        children[2] = empty_manager.clone();
        children[3] = NodeType::Ascii(new_key.clone());
        let template_name = match children.get(4) {
            Some(NodeType::Ascii(s)) => s.clone(),
            _ => String::new(),
        };
        blocks.push(block);
        scan.max_slot = slot_id;
        scan.max_garrison = garrison_id;
        report.push(format!("{}: added {} ({}, slot id {}, garrison id {})", key, new_key, template_name, slot_id, garrison_id));
    }
    esf.set_root_node(root);
    Ok(report)
}
