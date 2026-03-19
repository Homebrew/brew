use crate::BrewResult;
use crate::homebrew;
use anyhow::Context;
use serde::Deserialize;
use serde::de::DeserializeOwned;
use std::fs;
use std::path::Path;
use std::process::Command;

#[derive(Debug, Deserialize)]
pub(crate) struct Formula {
    pub(crate) name: String,
    #[serde(default)]
    pub(crate) full_name: Option<String>,
    #[serde(default)]
    pub(crate) desc: Option<String>,
    #[serde(default)]
    pub(crate) homepage: Option<String>,
    #[serde(default)]
    pub(crate) versions: Versions,
}

#[derive(Debug, Default, Deserialize)]
pub(crate) struct Versions {
    #[serde(default)]
    pub(crate) stable: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct Cask {
    pub(crate) token: String,
    #[serde(default)]
    pub(crate) name: Vec<String>,
    #[serde(default)]
    pub(crate) desc: Option<String>,
    #[serde(default)]
    pub(crate) homepage: Option<String>,
    #[serde(default)]
    pub(crate) version: Option<String>,
}

pub(crate) fn fetch_formula(name: &str) -> BrewResult<Option<Formula>> {
    fetch("formula", name)
}

pub(crate) fn fetch_cask(name: &str) -> BrewResult<Option<Cask>> {
    fetch("cask", name)
}

fn fetch<T: DeserializeOwned>(kind: &str, name: &str) -> BrewResult<Option<T>> {
    let cache_path = homebrew::cache_api_path()?
        .join(kind)
        .join(format!("{name}.json"));
    if let Some(json) = read_cached_json(&cache_path)? {
        return Ok(Some(json));
    }

    let endpoint = format!("{kind}/{name}.json");
    for api_domain in homebrew::api_domains()? {
        if let Some(body) = download_json(&format!("{api_domain}/{endpoint}"))? {
            return write_and_parse_json(&cache_path, &body).map(Some);
        }
    }

    Ok(None)
}

fn read_cached_json<T: DeserializeOwned>(path: &Path) -> BrewResult<Option<T>> {
    if !path.exists() {
        return Ok(None);
    }

    let bytes = fs::read(path).with_context(|| format!("Failed to read {}", path.display()))?;
    match serde_json::from_slice(&bytes) {
        Ok(json) => Ok(Some(json)),
        Err(_) => {
            let _ignored = fs::remove_file(path);
            Ok(None)
        }
    }
}

fn write_and_parse_json<T: DeserializeOwned>(path: &Path, bytes: &[u8]) -> BrewResult<T> {
    let json = serde_json::from_slice(bytes)
        .with_context(|| format!("Failed to parse {}", path.display()))?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create {}", parent.display()))?;
    }

    let temporary_path = path.with_extension("tmp");
    fs::write(&temporary_path, bytes)
        .with_context(|| format!("Failed to write {}", temporary_path.display()))?;
    fs::rename(&temporary_path, path)
        .with_context(|| format!("Failed to move {}", temporary_path.display()))?;

    Ok(json)
}

fn download_json(url: &str) -> BrewResult<Option<Vec<u8>>> {
    let mut command = Command::new(homebrew::curl());
    command
        .arg("--fail")
        .arg("--silent")
        .arg("--location")
        .arg("--compressed");

    if let Some(user_agent) = homebrew::user_agent_curl() {
        command.arg("--user-agent").arg(user_agent);
    }

    let output = command
        .arg(url)
        .output()
        .with_context(|| format!("Failed to download {url}"))?;

    if output.status.success() {
        Ok(Some(output.stdout))
    } else {
        Ok(None)
    }
}
