use crate::BrewResult;
use crate::delegate;
use crate::homebrew;
use anyhow::anyhow;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

#[derive(Default)]
struct Args<'a> {
    formula: bool,
    cask: bool,
    packages: Vec<&'a str>,
}

pub fn run(args: &[String]) -> BrewResult<ExitCode> {
    let parsed_args = {
        if let Some(formula_flag) = args
            .iter()
            .find(|s| matches!(s.as_str(), "--formula" | "--formulae"))
            && let Some(cask_flag) = args
                .iter()
                .find(|s| matches!(s.as_str(), "--cask" | "--casks"))
        {
            return Err(anyhow!(
                "Conflicting flags: `{}` and `{}`",
                formula_flag,
                cask_flag,
            ));
        }
        let mut result = Args::default();
        let mut args_iter = args.iter();
        args_iter.next(); // Skip `list`
        for arg in args_iter {
            match arg.as_str() {
                "--formula" | "--formulae" => result.formula = true,
                "--cask" | "--casks" => result.cask = true,
                s if !s.starts_with('-') && !s.contains('/') => result.packages.push(s),
                _ => return delegate::run(args),
            }
        }
        if !result.formula && !result.cask {
            result.formula = true;
            result.cask = true;
        }
        result
    };

    let cellar = homebrew::cellar_path()?;
    let prefix = homebrew::prefix_path()?;
    let caskroom = homebrew::caskroom_path()?;

    if parsed_args.packages.is_empty() {
        let formulae = if parsed_args.formula {
            homebrew::installed_names(&cellar)?
        } else {
            Vec::new()
        };
        let casks = if parsed_args.cask {
            homebrew::installed_names(&caskroom)?
        } else {
            Vec::new()
        };
        homebrew::print_sections(&formulae, &casks);
        return Ok(ExitCode::SUCCESS);
    }

    let mut missing = Vec::new();
    let mut listed_any = false;

    for name in parsed_args.packages {
        if parsed_args.formula {
            match list_formula_paths(&cellar, &prefix, name)? {
                FormulaPaths::Paths(paths) => {
                    if listed_any {
                        println!();
                    }
                    println!("{}", paths.join("\n"));
                    listed_any = true;
                    continue;
                }
                FormulaPaths::Delegate => return delegate::run(args),
                FormulaPaths::Missing => {}
            }
        }

        if parsed_args.cask
            && let Some(paths) = list_cask_paths(&caskroom, name)?
        {
            if listed_any {
                println!();
            }
            println!("{}", paths.join("\n"));
            listed_any = true;
            continue;
        }

        missing.push(name);
    }

    let keg_or_cask = if parsed_args.formula && parsed_args.cask {
        "keg or cask"
    } else if parsed_args.formula {
        "keg"
    } else {
        "cask"
    };

    if !missing.is_empty() {
        for name in missing {
            eprintln!("No such {keg_or_cask}: {name}");
        }
        return Ok(ExitCode::FAILURE);
    }

    Ok(ExitCode::SUCCESS)
}

enum FormulaPaths {
    Delegate,
    Missing,
    Paths(Vec<String>),
}

fn list_formula_paths(cellar: &Path, prefix: &Path, name: &str) -> BrewResult<FormulaPaths> {
    let rack = cellar.join(name);
    let versions = homebrew::installed_versions(&rack)?;
    if versions.is_empty() {
        return Ok(FormulaPaths::Missing);
    }

    if let Some(prefix) = current_keg_path(prefix, &rack, name)? {
        return list_formula_paths_in(&prefix);
    }

    if versions.len() == 1 {
        return list_formula_paths_in(&rack.join(&versions[0]));
    }

    Ok(FormulaPaths::Delegate)
}

fn current_keg_path(prefix: &Path, rack: &Path, name: &str) -> BrewResult<Option<PathBuf>> {
    for path in [
        prefix.join("opt").join(name),
        prefix.join("var/homebrew/linked").join(name),
    ] {
        let metadata = match fs::symlink_metadata(&path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            Err(error) => return Err(error.into()),
        };

        if metadata.file_type().is_symlink() && path.is_dir() {
            let resolved = fs::canonicalize(&path)?;
            if resolved.starts_with(rack) {
                return Ok(Some(resolved));
            }
        }
    }

    Ok(None)
}

fn list_formula_paths_in(prefix: &Path) -> BrewResult<FormulaPaths> {
    Ok(FormulaPaths::Paths(list_paths(prefix)?))
}

fn list_cask_paths(caskroom: &Path, name: &str) -> BrewResult<Option<Vec<String>>> {
    let cask_directory = caskroom.join(name);
    if !cask_directory.is_dir() {
        return Ok(None);
    }

    Ok(Some(list_paths(&cask_directory)?))
}

fn list_paths(path: &Path) -> BrewResult<Vec<String>> {
    Ok(homebrew::list_files(path)?
        .into_iter()
        .map(|path| path.display().to_string())
        .collect())
}

#[cfg(test)]
mod tests {
    use super::{FormulaPaths, current_keg_path, list_cask_paths, list_formula_paths};
    use std::env;
    use std::fs;
    use std::os::unix::fs::symlink;
    use std::path::{Path, PathBuf};
    use std::process;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn resolves_the_current_keg_from_opt() {
        let tempdir = TestDir::new_in(&env::current_dir().unwrap());
        let prefix = tempdir.path().join("prefix");
        let rack = tempdir.path().join("Cellar/foo");
        let linked_keg = rack.join("1.0");

        fs::create_dir_all(prefix.join("opt")).unwrap();
        fs::create_dir_all(&linked_keg).unwrap();
        symlink(&linked_keg, prefix.join("opt/foo")).unwrap();

        assert_eq!(
            current_keg_path(&prefix, &rack, "foo").unwrap(),
            Some(linked_keg)
        );
    }

    #[test]
    fn delegates_when_multiple_versions_are_installed_without_a_linked_keg() {
        let tempdir = TestDir::new_in(&env::current_dir().unwrap());
        let prefix = tempdir.path().join("prefix");
        let cellar = tempdir.path().join("Cellar");
        let rack = cellar.join("foo");

        fs::create_dir_all(prefix.join("opt")).unwrap();
        fs::create_dir_all(rack.join("1.0")).unwrap();
        fs::create_dir_all(rack.join("2.0")).unwrap();

        assert!(matches!(
            list_formula_paths(&cellar, &prefix, "foo").unwrap(),
            FormulaPaths::Delegate
        ));
    }

    #[test]
    fn returns_none_for_missing_casks() {
        let tempdir = TestDir::new_in(&env::current_dir().unwrap());
        assert!(
            list_cask_paths(tempdir.path(), "missing")
                .unwrap()
                .is_none()
        );
    }

    struct TestDir(PathBuf);

    impl TestDir {
        fn new_in(root: &Path) -> Self {
            static COUNTER: AtomicU64 = AtomicU64::new(0);
            let path = root.join(format!(
                "brew-rs-list-{}-{}-{}",
                process::id(),
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_nanos(),
                COUNTER.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
}
