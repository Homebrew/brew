use crate::BrewResult;
use crate::delegate;
use crate::homebrew;
use crate::json_api;
use std::path::Path;

pub(crate) fn run(args: &[String]) -> BrewResult<u8> {
    if args.len() < 2
        || args[1..]
            .iter()
            .any(|arg| arg.starts_with('-') || arg.contains('/'))
    {
        return delegate::run(args);
    }

    let cellar = homebrew::cellar_path()?;
    let caskroom = homebrew::caskroom_path()?;
    let mut sections = Vec::new();

    for name in &args[1..] {
        let formula = json_api::fetch_formula(name)?;
        let cask = json_api::fetch_cask(name)?;

        if let Some(formula) = formula.as_ref() {
            sections.push(render_formula_info(formula, &cellar)?);
        }
        if let Some(cask) = cask.as_ref() {
            sections.push(render_cask_info(cask, &caskroom)?);
        }
        if formula.is_none() && cask.is_none() {
            return delegate::run(args);
        }
    }

    println!("{}", sections.join("\n\n"));
    Ok(0)
}

fn render_formula_info(formula: &json_api::Formula, cellar: &Path) -> BrewResult<String> {
    let version = formula.versions.stable.as_deref().unwrap_or("unknown");
    let display_name = formula.full_name.as_deref().unwrap_or(&formula.name);
    let mut lines = vec![format!("{display_name}: {version}")];

    if let Some(desc) = formula.desc.as_deref() {
        lines.push(desc.to_string());
    }
    if let Some(homepage) = formula.homepage.as_deref() {
        lines.push(homepage.to_string());
    }

    let installed = homebrew::installed_versions(&cellar.join(&formula.name))?;
    if installed.is_empty() {
        lines.push("Not installed".to_string());
    } else {
        lines.push("Installed".to_string());
        lines.push(format!(
            "{} ({})",
            installed.join(", "),
            cellar.join(&formula.name).display()
        ));
    }

    Ok(lines.join("\n"))
}

fn render_cask_info(cask: &json_api::Cask, caskroom: &Path) -> BrewResult<String> {
    let version = cask.version.as_deref().unwrap_or("unknown");
    let mut lines = vec![format!("{}: {version}", cask.token)];

    if let Some(name) = cask.name.first() {
        lines.push(name.clone());
    }
    if let Some(desc) = cask.desc.as_deref() {
        lines.push(desc.to_string());
    }
    if let Some(homepage) = cask.homepage.as_deref() {
        lines.push(homepage.to_string());
    }

    let installed = homebrew::installed_versions(&caskroom.join(&cask.token))?;
    if installed.is_empty() {
        lines.push("Not installed".to_string());
    } else {
        lines.push("Installed".to_string());
        lines.push(format!(
            "{} ({})",
            installed.join(", "),
            caskroom.join(&cask.token).display()
        ));
    }

    Ok(lines.join("\n"))
}
