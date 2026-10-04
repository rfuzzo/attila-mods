// Spike: open a pack with rpfm_lib, count its files and export one DB table as TSV.
// usage: twpack <pack> <schema.ron> <destination folder>

use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};
use rpfm_lib::files::{pack::Pack, Container, ContainerPath};
use rpfm_lib::games::supported_games::{SupportedGames, KEY_ATTILA};
use rpfm_lib::schema::Schema;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 4 {
        return Err(anyhow!("usage: twpack <pack> <schema.ron> <destination folder>"));
    }

    let games = SupportedGames::default();
    let game = games.game(KEY_ATTILA).ok_or_else(|| anyhow!("no game info for Attila"))?;

    let mut pack = Pack::read_and_merge(&[PathBuf::from(&args[1])], game, true, false, false)?;
    println!("{}: {} files", args[1], pack.files().len());

    let schema = Some(Schema::load(Path::new(&args[2]), None)?);

    let tables: Vec<String> = pack
        .files()
        .keys()
        .filter(|path| path.to_lowercase().starts_with("db/regions_tables/"))
        .cloned()
        .collect();

    for table in tables {
        let written = pack.extract(ContainerPath::File(table.clone()), Path::new(&args[3]), true, &schema, false, true, &None)?;
        println!("{} -> {:?}", table, written);
    }

    Ok(())
}
