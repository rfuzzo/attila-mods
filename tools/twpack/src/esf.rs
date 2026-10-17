// ESF files (startpos.esf, saves, map data) as an indented text tree, to read and grep them.
//
// A record prints as `NAME` with its children indented below; a record with several blocks (a list of entries, e.g.
// one per region) prints each block as `NAME[i]`. Leaves print as `type value`, arrays on one line.

use std::fmt::Write;

use anyhow::{Context, Result};
use rpfm_lib::binary::ReadBytes;
use rpfm_lib::files::esf::{NodeType, ESF};
use rpfm_lib::files::{Decodeable, Encodeable};

pub fn decode(data: &[u8]) -> Result<ESF> {
    let mut cursor = std::io::Cursor::new(data);
    let esf = ESF::decode(&mut cursor, &None).context("decoding ESF")?;
    let read = cursor.position();
    let len = cursor.len()?;
    if read != len {
        eprintln!("warning: decoded {} of {} bytes", read, len);
    }
    Ok(esf)
}

pub fn encode(esf: &mut ESF) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    esf.encode(&mut out, &None).context("encoding ESF")?;
    Ok(out)
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
