// twpack: Total War pack tool for macOS (Attila), built on rpfm_lib.
//
//   twpack ls <pack> [pattern...]                     list files
//   twpack extract <pack> -o <dir> [pattern...] [-x pattern]  extract files (DB / loc as TSV)
//   twpack db export <pack> -o <dir> [table...]       export DB tables as TSV
//   twpack db import <pack> <tsv...>                  import TSV tables into an existing pack
//   twpack loc export <pack> -o <dir> [pattern...]    export loc files as TSV
//   twpack build <folder> -o <out.pack>               build a mod pack from a folder
//   twpack ui check|tree|export|import ...            binary UI layouts (see `twpack ui --help`)
//   twpack esf dump|check <file.esf> ...              ESF (startpos, saves) as an indented text tree / round-trip check
//
// Patterns are case-insensitive path prefixes, or globs if they contain `*`.

mod esf;
mod render;
mod uic;

use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use clap::{Args, Parser, Subcommand};
use rpfm_lib::error::RLibError;
use rpfm_lib::files::{pack::Pack, Container, ContainerPath, FileType};
use rpfm_lib::games::{pfh_file_type::PFHFileType, pfh_version::PFHVersion, supported_games::{SupportedGames, KEY_ATTILA}, GameInfo};
use rpfm_lib::schema::Schema;

const DEFAULT_SCHEMA: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../extracted/schemas/schema_att.ron");

#[derive(Parser)]
#[command(name = "twpack", about = "Total War: ATTILA pack tool (rpfm_lib)")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// List the files in a pack
    Ls {
        pack: PathBuf,
        /// Only list paths matching these patterns
        patterns: Vec<String>,
        /// Also show the file type
        #[arg(short, long)]
        long: bool,
    },
    /// Extract files, DB tables and loc files as TSV (unless --raw)
    Extract {
        pack: PathBuf,
        /// Only extract paths matching these patterns
        patterns: Vec<String>,
        #[arg(short, long)]
        out: PathBuf,
        /// Skip paths matching this pattern (repeatable), e.g. `-x '*.png'`
        #[arg(short = 'x', long)]
        exclude: Vec<String>,
        /// Extract DB tables and loc files as binary
        #[arg(long)]
        raw: bool,
        #[command(flatten)]
        schema: SchemaArg,
    },
    /// DB tables
    Db {
        #[command(subcommand)]
        command: DbCommand,
    },
    /// Localisation files
    Loc {
        #[command(subcommand)]
        command: LocCommand,
    },
    /// Binary UI layout files (`ui/...`, no extension, `Version0NN` header)
    Ui {
        #[command(subcommand)]
        command: UiCommand,
    },
    /// ESF files (startpos.esf, saves, map data)
    Esf {
        #[command(subcommand)]
        command: EsfCommand,
    },
    /// Build a mod pack (PFH4) from a folder; .tsv files become DB tables / loc files
    Build {
        folder: PathBuf,
        #[arg(short, long)]
        out: PathBuf,
        #[command(flatten)]
        schema: SchemaArg,
    },
}

#[derive(Subcommand)]
enum DbCommand {
    /// Export DB tables as TSV (all tables if none given)
    Export {
        pack: PathBuf,
        /// Table names, e.g. `regions` or `regions_tables`
        tables: Vec<String>,
        #[arg(short, long)]
        out: PathBuf,
        #[command(flatten)]
        schema: SchemaArg,
    },
    /// Import TSV tables into an existing pack, replacing files with the same path
    Import {
        pack: PathBuf,
        #[arg(required = true)]
        tsv: Vec<PathBuf>,
        #[command(flatten)]
        schema: SchemaArg,
    },
}

#[derive(Subcommand)]
enum EsfCommand {
    /// Print an ESF file as an indented text tree
    Dump {
        /// A loose .esf file, or a pack with --path
        file: PathBuf,
        /// Path of the ESF inside the pack given as `file`, e.g. `campaigns/main_attila/startpos.esf`
        #[arg(long)]
        path: Option<String>,
        /// Output file (stdout if omitted)
        #[arg(short, long)]
        out: Option<PathBuf>,
    },
    /// Decode and re-encode an ESF file and report whether it comes back byte-identical
    Check {
        /// A loose .esf file, or a pack with --path
        file: PathBuf,
        #[arg(long)]
        path: Option<String>,
    },
}

#[derive(Subcommand)]
enum LocCommand {
    /// Export loc files as TSV
    Export {
        pack: PathBuf,
        patterns: Vec<String>,
        #[arg(short, long)]
        out: PathBuf,
    },
}

#[derive(Subcommand)]
enum UiCommand {
    /// Decode and re-encode layouts (files or folders) and report any that don't come back byte-identical
    Check {
        #[arg(required = true)]
        paths: Vec<PathBuf>,
        /// Print every failure instead of the first 20
        #[arg(short, long)]
        all: bool,
    },
    /// Print a layout as an outline: components with their first state's size, offset, images, text and layout engine
    Tree {
        file: PathBuf,
        /// Also list states, images, animations
        #[arg(short, long)]
        verbose: bool,
    },
    /// Render a layout as a static HTML page (`<out>/index.html`) with the skin images it uses, to look at it without the game
    Render {
        layout: PathBuf,
        /// Output folder
        #[arg(short, long)]
        out: PathBuf,
        /// Packs to take images from (default: the game's data.pack and DLC packs); later packs win
        #[arg(long)]
        pack: Vec<PathBuf>,
        /// Render only the component with this name (the first one, depth first)
        #[arg(long)]
        only: Option<String>,
        /// Show this state of every component that has it (hover, down, ...) instead of the default state
        #[arg(long)]
        state: Option<String>,
        /// Also draw components whose visible flag is off (dashed outline)
        #[arg(long)]
        show_hidden: bool,
        #[arg(long, default_value_t = 1.0)]
        scale: f32,
    },
    /// Decode layouts (a file or a folder) to the YAML text form, `<name>.uic.yml`
    Export {
        path: PathBuf,
        /// Output file (stdout if omitted) or, for a folder, the output folder
        #[arg(short, long)]
        out: Option<PathBuf>,
        /// Leave out the ids of components, states and images nothing refers to by raw id (shorter; import makes new ones)
        #[arg(long)]
        no_uids: bool,
    },
    /// Encode the text form back into binary layouts: a `.uic.yml` file, or a folder of them
    Import {
        path: PathBuf,
        #[arg(short, long)]
        out: PathBuf,
    },
}

#[derive(Args)]
struct SchemaArg {
    /// Schema (.ron) for DB tables
    #[arg(long, default_value = DEFAULT_SCHEMA)]
    schema: PathBuf,
}

impl SchemaArg {
    fn load(&self) -> Result<Option<Schema>> {
        let schema = Schema::load(&self.schema, None).with_context(|| format!("loading schema {}", self.schema.display()))?;
        Ok(Some(schema))
    }
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let games = SupportedGames::default();
    let game = games.game(KEY_ATTILA).ok_or_else(|| anyhow!("no game info for Attila"))?;

    match cli.command {
        Command::Ls { pack, patterns, long } => {
            let pack = open(&pack, game)?;
            let mut stdout = io::stdout().lock();
            for path in matching(&pack, |path| matches_any(path, &patterns)) {
                let line = if long {
                    writeln!(stdout, "{:<12} {}", format!("{:?}", pack.files()[&path].file_type()), path)
                } else {
                    writeln!(stdout, "{}", path)
                };
                // Stop quietly when piped into `head`.
                if line.is_err() {
                    break;
                }
            }
        }
        Command::Extract { pack, patterns, out, exclude, raw, schema } => {
            let schema = if raw { None } else { schema.load()? };
            let mut pack = open(&pack, game)?;
            let paths = matching(&pack, |path| matches_any(path, &patterns) && (exclude.is_empty() || !matches_any(path, &exclude)));
            extract(&mut pack, paths, &out, &schema)?;
        }
        Command::Db { command: DbCommand::Export { pack, tables, out, schema } } => {
            let schema = schema.load()?;
            let mut pack = open(&pack, game)?;
            let prefixes: Vec<String> = tables
                .iter()
                .map(|table| {
                    let table = table.to_lowercase();
                    let table = table.strip_suffix("_tables").unwrap_or(&table);
                    format!("db/{}_tables/", table)
                })
                .collect();
            let paths = matching(&pack, |path| {
                pack.files()[path].file_type() == FileType::DB && (prefixes.is_empty() || prefixes.iter().any(|prefix| path.to_lowercase().starts_with(prefix)))
            });
            if paths.is_empty() {
                bail!("no matching DB tables");
            }
            extract(&mut pack, paths, &out, &schema)?;
        }
        Command::Db { command: DbCommand::Import { pack: pack_path, tsv, schema } } => {
            let schema = schema.load()?;
            let mut pack = Pack::read_and_merge(&[pack_path.clone()], game, false, false, false)
                .with_context(|| format!("opening {}", pack_path.display()))?;
            for file in &tsv {
                insert_tsv(&mut pack, file, &schema)?;
            }
            save(&mut pack, &pack_path, game)?;
        }
        Command::Loc { command: LocCommand::Export { pack, patterns, out } } => {
            let mut pack = open(&pack, game)?;
            let paths = matching(&pack, |path| pack.files()[path].file_type() == FileType::Loc && matches_any(path, &patterns));
            if paths.is_empty() {
                bail!("no matching loc files");
            }
            // Loc files don't need a schema, but extract only converts to TSV when it gets one.
            extract(&mut pack, paths, &out, &Some(Schema::default()))?;
        }
        Command::Ui { command } => ui(command, game)?,
        Command::Esf { command: EsfCommand::Dump { file, path, out } } => {
            let text = esf::dump(&esf::decode(&esf_data(&file, path.as_deref(), game)?)?);
            match out {
                Some(out) => write_file(&out, text)?,
                None => {
                    let _ = io::stdout().lock().write_all(text.as_bytes());
                }
            }
        }
        Command::Esf { command: EsfCommand::Check { file, path } } => {
            let data = esf_data(&file, path.as_deref(), game)?;
            let decoded = esf::decode(&data)?;
            let encoded = esf::encode(&mut decoded.clone())?;
            // rpfm_lib decodes a startpos from its compressed copy (`COMPRESSED_DATA`) and writes it differently, so
            // the bytes rarely match; what counts is that the re-encoded file reads back as the same tree.
            match esf::decode(&encoded) {
                Ok(tree) if tree == decoded => println!("re-encoded file decodes to the same tree"),
                Ok(_) => println!("re-encoded file decodes to a DIFFERENT tree"),
                Err(e) => println!("re-encoded file doesn't decode: {:#}", e),
            }
            match encoded.iter().zip(&data).position(|(a, b)| a != b) {
                None if encoded.len() == data.len() => println!("identical ({} bytes)", data.len()),
                None => println!("same up to {} bytes, then the lengths differ: {} encoded, {} original", encoded.len().min(data.len()), encoded.len(), data.len()),
                Some(at) => println!("differs at byte {:#x} ({} encoded, {} original)", at, encoded.len(), data.len()),
            }
        }
        Command::Build { folder, out, schema } => {
            let schema = schema.load()?;
            build(&folder, &out, &schema, game)?;
        }
    }

    Ok(())
}

/// An ESF's bytes: a loose file, or `path` inside the pack `file`.
fn esf_data(file: &Path, path: Option<&str>, game: &GameInfo) -> Result<Vec<u8>> {
    match path {
        Some(path) => {
            let mut pack = open(file, game)?;
            let key = matching(&pack, |p| p.eq_ignore_ascii_case(path)).into_iter().next().ok_or_else(|| anyhow!("{} not in {}", path, file.display()))?;
            let rfile = pack.files_mut().get_mut(&key).unwrap();
            rfile.load()?;
            Ok(rfile.cached()?.to_vec())
        }
        None => fs::read(file).with_context(|| format!("reading {}", file.display())),
    }
}

fn dirs_home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
}

/// Several packs merged into one (later ones win).
fn open_all(paths: &[PathBuf], game: &GameInfo) -> Result<Pack> {
    Pack::read_and_merge(paths, game, true, false, false).with_context(|| format!("opening {} packs", paths.len()))
}

fn open(path: &Path, game: &GameInfo) -> Result<Pack> {
    Pack::read_and_merge(&[path.to_path_buf()], game, true, false, false).with_context(|| format!("opening {}", path.display()))
}

/// Sorted paths of the pack's files that satisfy `filter`.
fn matching(pack: &Pack, filter: impl Fn(&String) -> bool) -> Vec<String> {
    let mut paths: Vec<String> = pack.files().keys().filter(|path| filter(path)).cloned().collect();
    paths.sort();
    paths
}

fn matches_any(path: &str, patterns: &[String]) -> bool {
    if patterns.is_empty() {
        return true;
    }
    let path = path.to_lowercase();
    patterns.iter().any(|pattern| {
        let pattern = pattern.to_lowercase().replace('\\', "/");
        if pattern.contains('*') {
            glob_match(pattern.as_bytes(), path.as_bytes())
        } else {
            path.starts_with(pattern.trim_start_matches('/'))
        }
    })
}

/// `*` matches any run of characters (including `/`).
fn glob_match(pattern: &[u8], text: &[u8]) -> bool {
    match pattern.split_first() {
        None => text.is_empty(),
        Some((b'*', rest)) => (0..=text.len()).any(|skip| glob_match(rest, &text[skip..])),
        Some((c, rest)) => text.first() == Some(c) && glob_match(rest, &text[1..]),
    }
}

fn extract(pack: &mut Pack, paths: Vec<String>, out: &Path, schema: &Option<Schema>) -> Result<()> {
    let mut failed = 0;
    let mut empty = 0;
    for path in &paths {
        let rfile = pack.files_mut().get_mut(path).ok_or_else(|| anyhow!("{} not found", path))?;
        // Export TSV ourselves: Container::extract silently falls back to binary when a table can't be decoded.
        if let (Some(schema), FileType::DB | FileType::Loc) = (schema, rfile.file_type()) {
            match rfile.tsv_export_to_path(&out.join(format!("{}.tsv", path)), schema, true) {
                Ok(()) => continue,
                // Tables CA shipped empty, often in versions the schema never saw. Nothing to lose.
                Err(RLibError::DecodingDBNoDefinitionsFoundAndEmptyFile) => empty += 1,
                Err(error) => {
                    eprintln!("warning: {}: {}, extracting as binary", path, error);
                    failed += 1;
                }
            }
        }
        pack.extract(ContainerPath::File(path.clone()), out, true, &None, false, true, &None)
            .with_context(|| format!("extracting {}", path))?;
    }
    println!("extracted {} files to {}", paths.len(), out.display());
    if empty > 0 {
        println!("{} empty tables without schema definition extracted as binary", empty);
    }
    if failed > 0 {
        eprintln!("{} DB / loc files could not be decoded and were extracted as binary", failed);
    }
    Ok(())
}

fn insert_tsv(pack: &mut Pack, file: &Path, schema: &Option<Schema>) -> Result<()> {
    // Import the TSV ourselves: insert_file silently falls back to adding it as a text file.
    let rfile = rpfm_lib::files::RFile::tsv_import_from_path(file, schema).with_context(|| format!("importing {}", file.display()))?;
    let path = rfile.path_in_container_raw().to_owned();
    pack.insert(rfile)?;
    println!("{} -> {}", file.display(), path);
    Ok(())
}

fn build(folder: &Path, out: &Path, schema: &Option<Schema>, game: &GameInfo) -> Result<()> {
    let mut pack = Pack::new_with_version(PFHVersion::PFH4);
    pack.set_pfh_file_type(PFHFileType::Mod);

    let mut files = vec![];
    walk(folder, &mut files)?;
    files.sort();

    for file in &files {
        let relative = file.strip_prefix(folder)?.to_string_lossy().replace('\\', "/");
        if file.extension().is_some_and(|ext| ext == "tsv") {
            insert_tsv(&mut pack, file, schema)?;
        } else if let Some(path) = relative.strip_suffix(UIC_TEXT_SUFFIX) {
            let data = encode_text_file(file)?;
            pack.insert(rpfm_lib::files::RFile::new_from_vec(&data, FileType::Unknown, 0, path))?;
            println!("{} -> {}", file.display(), path);
        } else {
            pack.insert_file(file, &relative, schema).with_context(|| format!("adding {}", file.display()))?;
        }
    }

    save(&mut pack, out, game)?;
    println!("built {} with {} files", out.display(), files.len());
    Ok(())
}

/// All files below `dir`, skipping hidden files and folders (.DS_Store, .git).
fn walk(dir: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
    for entry in fs::read_dir(dir).with_context(|| format!("reading {}", dir.display()))? {
        let entry = entry?;
        if entry.file_name().to_string_lossy().starts_with('.') {
            continue;
        }
        let path = entry.path();
        if entry.file_type()?.is_dir() {
            walk(&path, files)?;
        } else {
            files.push(path);
        }
    }
    Ok(())
}

fn save(pack: &mut Pack, path: &Path, game: &GameInfo) -> Result<()> {
    if let Some(parent) = path.parent().filter(|parent| !parent.as_os_str().is_empty()) {
        fs::create_dir_all(parent)?;
    }
    pack.save(Some(path), game, &None).with_context(|| format!("saving {}", path.display()))
}

const UIC_TEXT_SUFFIX: &str = ".uic.yml";

/// Files below `path` (or `path` itself) that start with a layout header, with their path relative to `path`.
fn layout_files(path: &Path) -> Result<Vec<(PathBuf, PathBuf)>> {
    let mut files = Vec::new();
    if path.is_dir() {
        walk(path, &mut files)?;
    } else {
        files.push(path.to_path_buf());
    }
    files.sort();
    let mut found = Vec::new();
    for file in files {
        let mut header = [0u8; 10];
        let is_layout = fs::File::open(&file).and_then(|mut f| io::Read::read_exact(&mut f, &mut header)).is_ok() && uic::looks_like_layout(&header);
        if is_layout {
            let relative = if path.is_dir() { file.strip_prefix(path)?.to_path_buf() } else { file.file_name().map(PathBuf::from).unwrap_or_default() };
            found.push((file, relative));
        }
    }
    Ok(found)
}

fn write_file(path: &Path, data: impl AsRef<[u8]>) -> Result<()> {
    if let Some(parent) = path.parent().filter(|parent| !parent.as_os_str().is_empty()) {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, data).with_context(|| format!("writing {}", path.display()))
}

/// Encode the text of a `.uic.yml` file.
fn encode_text_file(file: &Path) -> Result<Vec<u8>> {
    let layout = uic::from_text(&fs::read_to_string(file)?).with_context(|| file.display().to_string())?;
    uic::encode(&layout).with_context(|| file.display().to_string())
}

fn ui(command: UiCommand, game: &GameInfo) -> Result<()> {
    match command {
        UiCommand::Check { paths, all } => {
            let mut files = Vec::new();
            for path in &paths {
                files.extend(layout_files(path)?.into_iter().map(|(file, _)| file));
            }
            // version -> (ok, failed)
            let mut versions: std::collections::BTreeMap<String, (usize, usize)> = Default::default();
            let mut failures = Vec::new();
            for file in files {
                let data = fs::read(&file).with_context(|| format!("reading {}", file.display()))?;
                let version = String::from_utf8_lossy(&data[7..10]).to_string();
                let result = check_layout(&data);
                let entry = versions.entry(version).or_default();
                match result {
                    Ok(()) => entry.0 += 1,
                    Err(e) => {
                        entry.1 += 1;
                        failures.push(format!("{}: {:#}", file.display(), e));
                    }
                }
            }
            for (version, (ok, failed)) in &versions {
                println!("v{}: {} ok, {} failed", version, ok, failed);
            }
            let limit = if all { failures.len() } else { 20 };
            failures.iter().take(limit).for_each(|f| println!("  {}", f));
            if failures.len() > limit {
                println!("  ... and {} more (--all)", failures.len() - limit);
            }
            if !failures.is_empty() {
                bail!("{} layouts failed", failures.len());
            }
        }
        UiCommand::Tree { file, verbose } => {
            let layout = uic::decode(&fs::read(&file)?).with_context(|| file.display().to_string())?;
            let mut text = format!("Version{:03}\n", layout.version);
            print_tree(&layout.root, 0, verbose, &mut text);
            // Stop quietly when piped into `head`.
            let _ = io::stdout().write_all(text.as_bytes());
        }
        UiCommand::Render { layout, out, pack, only, state, show_hidden, scale } => {
            let decoded = uic::decode(&fs::read(&layout)?).with_context(|| layout.display().to_string())?;
            let title = layout.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            let opts = render::Options { only, state, show_hidden, scale };
            let page = render::render(&decoded, &title, &opts).map_err(|e| anyhow!(e))?;
            write_file(&out.join("index.html"), &page.html)?;
            let packs = if pack.is_empty() {
                let data = dirs_home().join("Library/Application Support/Steam/steamapps/common/Total War Attila/TotalWarAttilaData/data");
                ["data", "belisarius", "charlemagne", "slavs"].iter().map(|n| data.join(format!("{}.pack", n))).filter(|p| p.exists()).collect()
            } else {
                pack
            };
            let mut pack = open_all(&packs, game)?;
            let by_lowercase: std::collections::HashMap<String, String> = pack.files().keys().map(|k| (k.to_lowercase(), k.clone())).collect();
            let mut missing = Vec::new();
            for image in &page.images {
                match by_lowercase.get(image) {
                    Some(key) => {
                        pack.extract(ContainerPath::File(key.clone()), &out, true, &None, false, true, &None).with_context(|| format!("extracting {}", key))?;
                    }
                    None => missing.push(image.clone()),
                }
            }
            println!("{}: {} images ({} not found in the packs)", out.join("index.html").display(), page.images.len(), missing.len());
            missing.iter().take(10).for_each(|m| println!("  missing {}", m));
        }
        UiCommand::Export { path, out, no_uids } => {
            if path.is_dir() {
                let out = out.ok_or_else(|| anyhow!("exporting a folder needs -o <folder>"))?;
                let (mut done, mut skipped) = (0, 0);
                for (file, relative) in layout_files(&path)? {
                    let text = uic::decode(&fs::read(&file)?).and_then(|layout| uic::to_text(&layout, !no_uids));
                    match text {
                        Ok(text) => {
                            write_file(&out.join(format!("{}{}", relative.display(), UIC_TEXT_SUFFIX)), text)?;
                            done += 1;
                        }
                        Err(e) => {
                            eprintln!("skipped {}: {:#}", file.display(), e);
                            skipped += 1;
                        }
                    }
                }
                println!("exported {} layouts to {} ({} skipped)", done, out.display(), skipped);
            } else {
                let layout = uic::decode(&fs::read(&path)?).with_context(|| path.display().to_string())?;
                let text = uic::to_text(&layout, !no_uids)?;
                match out {
                    Some(out) => write_file(&out, text)?,
                    None => {
                        let _ = io::stdout().write_all(text.as_bytes());
                    }
                }
            }
        }
        UiCommand::Import { path, out } => {
            if path.is_dir() {
                let mut files = Vec::new();
                walk(&path, &mut files)?;
                files.sort();
                let mut done = 0;
                for file in files {
                    let relative = file.strip_prefix(&path)?.to_string_lossy().to_string();
                    if let Some(name) = relative.strip_suffix(UIC_TEXT_SUFFIX) {
                        write_file(&out.join(name), encode_text_file(&file)?)?;
                        done += 1;
                    }
                }
                println!("imported {} layouts to {}", done, out.display());
            } else {
                write_file(&out, encode_text_file(&path)?)?;
            }
        }
    }
    Ok(())
}

/// Binary -> layout -> binary must give the same bytes; layout -> text -> layout the same layout (with and without ids).
fn check_layout(data: &[u8]) -> Result<()> {
    let layout = uic::decode(data)?;
    let back = uic::encode(&layout)?;
    if let Some(at) = back.iter().zip(data).position(|(a, b)| a != b).or((back.len() != data.len()).then(|| back.len().min(data.len()))) {
        bail!("re-encoded differs (first difference at {:#x}, {} vs {} bytes)", at, back.len(), data.len());
    }
    let text = uic::to_text(&layout, true)?;
    let again = uic::encode(&uic::from_text(&text).context("reading the text form")?)?;
    if again != data {
        bail!("text form (with ids) doesn't give the same file back");
    }
    // Without ids the ids are made up again, so compare what's written: the same text must come out.
    let short = uic::to_text(&layout, false)?;
    let regenerated = uic::to_text(&uic::from_text(&short).context("reading the short text form")?, false)?;
    if short != regenerated {
        bail!("text form (without ids) changes when read and written again");
    }
    Ok(())
}

fn print_tree(u: &uic::Uic, depth: usize, verbose: bool, out: &mut String) {
    let indent = "  ".repeat(depth);
    let mut line = format!("{}{}", indent, u.name);
    if let Some(state) = u.states.first() {
        line += &format!("  {}x{} @ {},{}", state.bounds.0[0], state.bounds.0[1], u.offset.0[0], u.offset.0[1]);
        if !state.text_label.is_empty() || !state.text.is_empty() {
            line += &format!("  text={:?}", if state.text_label.is_empty() { &state.text } else { &state.text_label });
        }
    }
    if !u.tail.kind.is_empty() {
        line += &format!("  [{}]", u.tail.kind);
    }
    out.push_str(&line);
    out.push('\n');
    if verbose {
        for state in &u.states {
            out.push_str(&format!("{}  state {} {}x{} {} images\n", indent, state.name, state.bounds.0[0], state.bounds.0[1], state.image_metrics.len()));
        }
        for image in &u.images {
            out.push_str(&format!("{}  image {} {}x{}\n", indent, image.path, image.width, image.height));
        }
        for func in &u.funcs {
            out.push_str(&format!("{}  anim {} ({} steps)\n", indent, func.name, func.anims.len()));
        }
    }
    for child in &u.children {
        print_tree(child, depth + 1, verbose, out);
    }
}
