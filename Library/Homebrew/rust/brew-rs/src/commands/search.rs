use crate::BrewResult;
use crate::delegate;
use crate::homebrew;
use crate::matcher::Matcher;

pub(crate) fn run(args: &[String]) -> BrewResult<u8> {
    if args.len() != 2 || args[1].starts_with('-') {
        return delegate::run(args);
    }

    let formula_names =
        match homebrew::read_lines(&homebrew::cache_api_path()?.join("formula_names.txt")) {
            Ok(names) if !names.is_empty() => names,
            _ => return delegate::run(args),
        };
    let cask_names = match homebrew::read_lines(&homebrew::cache_api_path()?.join("cask_names.txt"))
    {
        Ok(names) => names,
        Err(_) => return delegate::run(args),
    };

    let matcher = Matcher::try_from(args[1].as_str())?;
    let matched_formulae = formula_names
        .into_iter()
        .filter(|name| matcher.matches(name))
        .collect::<Vec<_>>();
    let matched_casks = cask_names
        .into_iter()
        .filter(|name| matcher.matches(name))
        .collect::<Vec<_>>();

    if matched_formulae.is_empty() && matched_casks.is_empty() {
        eprintln!("No formulae or casks found for {:?}.", args[1]);
        return Ok(1);
    }

    homebrew::print_sections(&matched_formulae, &matched_casks);
    Ok(0)
}
