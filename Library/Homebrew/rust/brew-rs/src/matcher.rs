use crate::BrewResult;
use regex::Regex;

pub(crate) enum Matcher {
    Regex(Regex),
    String(String),
}

impl TryFrom<&str> for Matcher {
    type Error = anyhow::Error;

    fn try_from(query: &str) -> BrewResult<Self> {
        if query.len() > 2 && query.starts_with('/') && query.ends_with('/') {
            Regex::new(&query[1..query.len() - 1])
                .map(Self::Regex)
                .map_err(|error| anyhow::anyhow!("{query} is not a valid regex: {error}"))
        } else {
            Ok(Self::String(simplify_string(query)))
        }
    }
}

impl Matcher {
    pub(crate) fn matches(&self, value: &str) -> bool {
        match self {
            Self::Regex(regex) => regex.is_match(value),
            Self::String(string) => simplify_string(value).contains(string),
        }
    }
}

fn simplify_string(value: &str) -> String {
    value
        .chars()
        .filter_map(|character| {
            let lowered = character.to_ascii_lowercase();
            if lowered.is_ascii_alphanumeric() || lowered == '@' || lowered == '+' {
                Some(lowered)
            } else {
                None
            }
        })
        .collect()
}
