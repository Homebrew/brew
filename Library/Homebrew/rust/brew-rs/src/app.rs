use crate::BrewResult;
use crate::commands;
use crate::delegate;
use std::env;
use std::process::ExitCode;

pub(crate) fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("{error}");
            ExitCode::from(1)
        }
    }
}

fn run() -> BrewResult<u8> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.is_empty() {
        return delegate::run(&args);
    }

    match args[0].as_str() {
        "search" => commands::search::run(&args),
        "info" => commands::info::run(&args),
        "list" => commands::list::run(&args),
        "install" => commands::install::run(&args),
        "update" => commands::update::run(&args),
        "upgrade" => commands::upgrade::run(&args),
        "uninstall" => commands::uninstall::run(&args),
        _ => delegate::run(&args),
    }
}
