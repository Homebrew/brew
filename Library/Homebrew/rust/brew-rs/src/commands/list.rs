use crate::BrewResult;
use crate::delegate;
use crate::homebrew;
use std::path::Path;

pub(crate) fn run(args: &[String]) -> BrewResult<u8> {
    if args[1..]
        .iter()
        .any(|arg| arg.starts_with('-') || arg.contains('/'))
    {
        return delegate::run(args);
    }

    let cellar = homebrew::cellar_path()?;
    let caskroom = homebrew::caskroom_path()?;

    if args.len() == 1 {
        let formulae = homebrew::installed_names(&cellar)?;
        let casks = homebrew::installed_names(&caskroom)?;
        homebrew::print_sections(&formulae, &casks);
        return Ok(0);
    }

    let mut missing = Vec::new();
    let mut listed_any = false;

    for name in &args[1..] {
        if let Some(paths) = list_formula_paths(&cellar, name)? {
            if listed_any {
                println!();
            }
            println!("{}", paths.join("\n"));
            listed_any = true;
            continue;
        }

        if let Some(paths) = list_cask_paths(&caskroom, name)? {
            if listed_any {
                println!();
            }
            println!("{}", paths.join("\n"));
            listed_any = true;
            continue;
        }

        missing.push(name.clone());
    }

    if !missing.is_empty() {
        for name in missing {
            eprintln!("No such keg or cask: {name}");
        }
        return Ok(1);
    }

    Ok(0)
}

fn list_formula_paths(cellar: &Path, name: &str) -> BrewResult<Option<Vec<String>>> {
    let rack = cellar.join(name);
    let versions = homebrew::installed_versions(&rack)?;
    let Some(version) = versions.last() else {
        return Ok(None);
    };

    let prefix = rack.join(version);
    Ok(Some(
        homebrew::list_files(&prefix)?
            .into_iter()
            .map(|path| path.display().to_string())
            .collect(),
    ))
}

fn list_cask_paths(caskroom: &Path, name: &str) -> BrewResult<Option<Vec<String>>> {
    let cask_directory = caskroom.join(name);
    if !cask_directory.is_dir() {
        return Ok(None);
    }

    Ok(Some(
        homebrew::list_files(&cask_directory)?
            .into_iter()
            .map(|path| path.display().to_string())
            .collect(),
    ))
}
