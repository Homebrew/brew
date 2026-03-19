#![forbid(unsafe_code)]

mod app;
mod commands;
mod delegate;
mod homebrew;
mod json_api;
mod matcher;

use anyhow::Result;
use std::process::ExitCode;

pub fn main() -> ExitCode {
    app::main()
}

type BrewResult<T> = Result<T>;
