use crate::BrewResult;
use anyhow::{Context, anyhow};
use std::env;
use std::fs;
use std::io::{self, IsTerminal};
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

pub(crate) fn cache_api_path() -> BrewResult<PathBuf> {
    Ok(env_path("HOMEBREW_CACHE")?.join("api"))
}

pub(crate) fn cellar_path() -> BrewResult<PathBuf> {
    env_path("HOMEBREW_CELLAR")
}

pub(crate) fn caskroom_path() -> BrewResult<PathBuf> {
    env_path("HOMEBREW_CASKROOM")
}

pub(crate) fn brew_file() -> BrewResult<PathBuf> {
    env_path("HOMEBREW_BREW_FILE")
}

pub(crate) fn curl() -> String {
    env::var("HOMEBREW_CURL").unwrap_or_else(|_| "curl".to_string())
}

pub(crate) fn user_agent_curl() -> Option<String> {
    env::var("HOMEBREW_USER_AGENT_CURL")
        .ok()
        .filter(|value| !value.is_empty())
}

pub(crate) fn api_domains() -> BrewResult<Vec<String>> {
    let default_api_domain = env::var("HOMEBREW_API_DEFAULT_DOMAIN")
        .context("HOMEBREW_API_DEFAULT_DOMAIN is not set")?;
    let api_domain = env::var("HOMEBREW_API_DOMAIN").unwrap_or_else(|_| default_api_domain.clone());

    if api_domain == default_api_domain {
        Ok(vec![default_api_domain])
    } else {
        Ok(vec![api_domain, default_api_domain])
    }
}

pub(crate) fn read_lines(path: &Path) -> BrewResult<Vec<String>> {
    let contents =
        fs::read_to_string(path).with_context(|| format!("Failed to read {}", path.display()))?;
    Ok(contents
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToString::to_string)
        .collect())
}

pub(crate) fn installed_names(path: &Path) -> BrewResult<Vec<String>> {
    list_directories(path)
}

pub(crate) fn installed_versions(path: &Path) -> BrewResult<Vec<String>> {
    list_directories(path)
}

pub(crate) fn list_files(path: &Path) -> BrewResult<Vec<PathBuf>> {
    if !path.exists() {
        return Err(anyhow!("Failed to list {}", path.display()));
    }

    let mut files = WalkDir::new(path)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .map(|entry| entry.into_path())
        .collect::<Vec<_>>();
    files.sort();
    Ok(files)
}

pub(crate) fn print_sections(formulae: &[String], casks: &[String]) {
    let stdout_is_tty = io::stdout().is_terminal();

    if stdout_is_tty && !formulae.is_empty() && !casks.is_empty() {
        println!("Formulae");
        println!("{}", formulae.join("\n"));
        println!();
        println!("Casks");
        println!("{}", casks.join("\n"));
        return;
    }

    if !formulae.is_empty() {
        println!("{}", formulae.join("\n"));
    }
    if !formulae.is_empty() && !casks.is_empty() {
        println!();
    }
    if !casks.is_empty() {
        println!("{}", casks.join("\n"));
    }
}

fn env_path(name: &str) -> BrewResult<PathBuf> {
    env::var_os(name)
        .map(PathBuf::from)
        .ok_or_else(|| anyhow!("{name} is not set"))
}

fn list_directories(path: &Path) -> BrewResult<Vec<String>> {
    if !path.exists() {
        return Ok(Vec::new());
    }

    let mut entries = fs::read_dir(path)
        .with_context(|| format!("Failed to list {}", path.display()))?
        .collect::<std::result::Result<Vec<_>, _>>()
        .with_context(|| format!("Failed to list {}", path.display()))?;
    entries.sort_by_key(|entry| entry.file_name());

    Ok(entries
        .into_iter()
        .filter_map(|entry| {
            entry
                .file_type()
                .ok()
                .filter(|file_type| file_type.is_dir())
                .map(|_| entry)
        })
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect())
}
