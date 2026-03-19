use crate::BrewResult;
use crate::homebrew;
use anyhow::Context;
use std::process::{Command, Stdio};

pub(crate) fn run(args: &[String]) -> BrewResult<u8> {
    let status = Command::new(homebrew::brew_file()?)
        .args(args)
        .env("HOMEBREW_RUST_FRONTEND_INTERNAL", "1")
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .context("Failed to delegate to brew")?;

    Ok(status.code().unwrap_or(1).clamp(0, 255) as u8)
}
