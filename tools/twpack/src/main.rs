// twpack: Total War pack tool for macOS (Attila), built on rpfm_lib.
//
//   twpack ls <pack> [pattern...]                     list files
//   twpack extract <pack> -o <dir> [pattern...] [-x pattern]  extract files (DB / loc as TSV)
//   twpack db export <pack> -o <dir> [table...]       export DB tables as TSV
//   twpack db import <pack> <tsv...>                  import TSV tables into an existing pack
//   twpack loc export <pack> -o <dir> [pattern...]    export loc files as TSV
//   twpack build <folder> -o <out.pack>               build a mod pack from a folder
//
// Patterns are case-insensitive path prefixes, or globs if they contain `*`.

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
enum LocCommand {
    /// Export loc files as TSV
    Export {
        pack: PathBuf,
        patterns: Vec<String>,
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
        Command::Build { folder, out, schema } => {
            let schema = schema.load()?;
            build(&folder, &out, &schema, game)?;
        }
    }

    Ok(())
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
