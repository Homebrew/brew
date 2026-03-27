use crate::BrewResult;
use crate::delegate;
use crate::homebrew;
use crate::matcher::Matcher;
use rust_fuzzy_search::fuzzy_search_threshold;
use std::process::ExitCode;

#[derive(Default)]
struct Args<'a> {
    formula: bool,
    cask: bool,
    package_name: Option<&'a str>,
}

pub fn run(args: &[String]) -> BrewResult<ExitCode> {
    let parsed_args = {
        let mut result = Args::default();
        let mut args_iter = args.iter();
        args_iter.next(); // Skip `search`
        for arg in args_iter {
            match arg.as_str() {
                "--formula" | "--formulae" => result.formula = true,
                "--cask" | "--casks" => result.cask = true,
                s if !s.starts_with('-') && result.package_name.is_none() => {
                    result.package_name = Some(s)
                }
                _ => return delegate::run(args),
            }
        }
        if !result.formula && !result.cask {
            result.formula = true;
            result.cask = true;
        }
        result
    };

    let api_cache = homebrew::cache_api_path()?;
    let formula_names = match homebrew::read_lines(&api_cache.join("formula_names.txt")) {
        Ok(names) if !names.is_empty() => names,
        _ => return delegate::run(args),
    };
    let cask_names = match homebrew::read_lines(&api_cache.join("cask_names.txt")) {
        Ok(names) => names,
        Err(_) => return delegate::run(args),
    };

    let package_name = match parsed_args.package_name {
        Some(package_name) => package_name,
        _ => return delegate::run(args),
    };

    let matcher = Matcher::try_from(package_name)?;
    let matched_formulae = if parsed_args.formula {
        matched_names(&formula_names, &matcher)
    } else {
        Vec::new()
    };
    let matched_casks = if parsed_args.cask {
        matched_names(&cask_names, &matcher)
    } else {
        Vec::new()
    };

    let formulae_or_casks = if parsed_args.formula && parsed_args.cask {
        "formulae or casks"
    } else if parsed_args.formula {
        "formulae"
    } else {
        "casks"
    };

    if matched_formulae.is_empty() && matched_casks.is_empty() {
        eprintln!("No {formulae_or_casks} found for {:?}.", package_name);
        return Ok(ExitCode::FAILURE);
    }

    homebrew::print_sections(&matched_formulae, &matched_casks);
    Ok(ExitCode::SUCCESS)
}

fn matched_names(names: &[String], matcher: &Matcher) -> Vec<String> {
    let matched_names = names
        .iter()
        .filter(|name| matcher.matches(name))
        .cloned()
        .collect::<Vec<_>>();
    if !matched_names.is_empty() {
        return matched_names;
    }

    let Matcher::String(query) = matcher else {
        return matched_names;
    };
    if query.len() < 3 {
        return matched_names;
    }

    let candidates = names.iter().map(String::as_str).collect::<Vec<_>>();
    let mut similar = fuzzy_search_threshold(query, &candidates, 0.5);
    similar.sort_by(|(_, left), (_, right)| right.total_cmp(left));
    similar
        .into_iter()
        .map(|(name, _)| name.to_string())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::matched_names;
    use crate::matcher::Matcher;

    #[test]
    fn returns_plain_text_matches_before_fuzzy_results() {
        let names = vec!["testball".to_string(), "another".to_string()];
        let matcher = Matcher::try_from("testball").unwrap();

        assert_eq!(
            matched_names(&names, &matcher),
            vec!["testball".to_string()]
        );
    }

    #[test]
    fn returns_fuzzy_matches_for_long_plain_text_queries() {
        let names = vec!["testball".to_string(), "other".to_string()];
        let matcher = Matcher::try_from("testbal").unwrap();

        assert_eq!(
            matched_names(&names, &matcher),
            vec!["testball".to_string()]
        );
    }

    #[test]
    fn does_not_use_fuzzy_matching_for_short_queries() {
        let names = vec!["foo-bar".to_string()];
        let matcher = Matcher::try_from("fb").unwrap();

        assert!(matched_names(&names, &matcher).is_empty());
    }

    #[test]
    fn does_not_use_fuzzy_matching_for_regex_queries() {
        let names = vec!["testball".to_string()];
        let matcher = Matcher::try_from("/foo/").unwrap();

        assert!(matched_names(&names, &matcher).is_empty());
    }
}
