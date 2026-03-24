use crate::BrewResult;
use crate::homebrew;
use std::env;
use std::path::Path;
use std::process::{Command, ExitCode};

pub fn run(_args: &[String]) -> BrewResult<ExitCode> {
    print_homebrew_config()?;
    print_core_tap_json()?;
    print_env_config();
    print_system_config();
    print_host_software();
    Ok(ExitCode::SUCCESS)
}

fn print_homebrew_config() -> BrewResult<()> {
    let repo = env::var("HOMEBREW_REPOSITORY").unwrap_or_default();

    println!(
        "HOMEBREW_VERSION: {}",
        env::var("HOMEBREW_VERSION").unwrap_or_default()
    );
    println!(
        "ORIGIN: {}",
        git_output(&repo, &["config", "remote.origin.url"])
    );
    println!("HEAD: {}", git_output(&repo, &["rev-parse", "HEAD"]));
    println!(
        "Last commit: {}",
        git_output(&repo, &["log", "-1", "--format=%cr"])
    );
    println!(
        "Branch: {}",
        git_output(&repo, &["symbolic-ref", "--short", "HEAD"])
    );
    Ok(())
}

fn print_core_tap_json() -> BrewResult<()> {
    let cache = homebrew::cache_api_path()?;
    for (label, filename) in [
        ("Core tap JSON", "formula.jws.json"),
        ("Core cask tap JSON", "cask.jws.json"),
    ] {
        let path = cache.join(filename);
        if path.exists() {
            if let Ok(meta) = path.metadata() {
                if let Ok(mtime) = meta.modified() {
                    let secs = mtime
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_secs();
                    println!("{label}: {}", format_utc_timestamp(secs));
                    continue;
                }
            }
        }
        println!("{label}: N/A");
    }
    Ok(())
}

fn print_env_config() {
    println!(
        "HOMEBREW_PREFIX: {}",
        env::var("HOMEBREW_PREFIX").unwrap_or_default()
    );

    for key in [
        "HOMEBREW_CASK_OPTS",
        "HOMEBREW_DOWNLOAD_CONCURRENCY",
        "HOMEBREW_EDITOR",
        "HOMEBREW_MAKE_JOBS",
    ] {
        if let Ok(val) = env::var(key) {
            println!("{key}: {val}");
        }
    }

    for key in [
        "HOMEBREW_FORBID_PACKAGES_FROM_PATHS",
        "HOMEBREW_SORBET_RUNTIME",
        "HOMEBREW_NO_AUTO_UPDATE",
        "HOMEBREW_NO_INSTALL_CLEANUP",
        "HOMEBREW_NO_ANALYTICS",
    ] {
        if env::var(key).is_ok() {
            println!("{key}: set");
        }
    }

    println!(
        "Homebrew Ruby: {}",
        env::var("HOMEBREW_RUBY_VERSION")
            .map(|v| {
                let ruby_path = env::var("HOMEBREW_RUBY_PATH").unwrap_or_default();
                if ruby_path.is_empty() {
                    v
                } else {
                    format!("{v} => {ruby_path}")
                }
            })
            .unwrap_or_else(|_| "N/A".to_string())
    );
}

fn print_system_config() {
    let cpu = cpu_info();
    if !cpu.is_empty() {
        println!("CPU: {cpu}");
    }

    let macos = macos_version();
    if !macos.is_empty() {
        println!("macOS: {macos}");
    }

    let clt = command_first_line("xcode-select", &["--version"]);
    if !clt.is_empty() {
        let version = clt
            .strip_prefix("xcode-select version ")
            .unwrap_or(&clt)
            .trim_end_matches('.');
        println!("CLT: {version}");
    }

    let xcode = command_first_line("xcodebuild", &["-version"]);
    if !xcode.is_empty() {
        let version = xcode.strip_prefix("Xcode ").unwrap_or(&xcode);
        println!("Xcode: {version}");
    }
}

fn print_host_software() {
    println!("Clang: {}", clang_version());
    println!("Git: {}", tool_version_with_path("git"));
    println!("Curl: {}", curl_version());
}

fn git_output(repo: &str, args: &[&str]) -> String {
    if repo.is_empty() || !Path::new(repo).exists() {
        return "N/A".to_string();
    }
    Command::new("git")
        .args(["-C", repo])
        .args(args)
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_else(|| "N/A".to_string())
}

fn command_first_line(cmd: &str, args: &[&str]) -> String {
    Command::new(cmd)
        .args(args)
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .next()
                .map(|s| s.trim().to_string())
        })
        .unwrap_or_default()
}

fn cpu_info() -> String {
    let arch = std::env::consts::ARCH;
    let cores = command_first_line("sysctl", &["-n", "hw.ncpu"]);
    if cores.is_empty() {
        return String::new();
    }
    let brand = command_first_line("sysctl", &["-n", "machdep.cpu.brand_string"]);
    if brand.is_empty() {
        format!("{cores}-core 64-bit {arch}")
    } else {
        format!("{cores}-core 64-bit {arch} ({brand})")
    }
}

fn macos_version() -> String {
    let version = command_first_line("sw_vers", &["-productVersion"]);
    if version.is_empty() {
        return String::new();
    }
    let arch = std::env::consts::ARCH;
    let arch_suffix = match arch {
        "aarch64" => "arm64",
        other => other,
    };
    format!("{version}-{arch_suffix}")
}

fn clang_version() -> String {
    let output = Command::new("clang")
        .arg("--version")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default();

    if output.is_empty() {
        return "N/A".to_string();
    }

    // Parse "Apple clang version 17.0.0 (clang-1700.0.13.3)" or similar
    let version = output
        .lines()
        .next()
        .and_then(|line| {
            line.split_whitespace()
                .find(|word| word.chars().next().is_some_and(|c| c.is_ascii_digit()))
        })
        .unwrap_or("N/A");

    // Extract build number from parenthesized clang-NNNN
    let build = output
        .lines()
        .next()
        .and_then(|line| {
            line.find("clang-").map(|i| {
                let rest = &line[i + 6..];
                rest.split(|c: char| !c.is_ascii_digit())
                    .next()
                    .unwrap_or("")
            })
        })
        .unwrap_or("");

    if build.is_empty() {
        version.to_string()
    } else {
        format!("{version} build {build}")
    }
}

fn tool_version_with_path(tool: &str) -> String {
    let path = Command::new("which")
        .arg(tool)
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();

    let version_output = Command::new(tool)
        .arg("--version")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default();

    let version = version_output
        .lines()
        .next()
        .and_then(|line| {
            line.split_whitespace()
                .find(|word| word.chars().next().is_some_and(|c| c.is_ascii_digit()))
        })
        .unwrap_or("N/A");

    if path.is_empty() {
        version.to_string()
    } else {
        format!("{version} => {path}")
    }
}

fn curl_version() -> String {
    let output = command_first_line("curl", &["--version"]);
    if output.is_empty() {
        return "N/A".to_string();
    }

    let version = output
        .strip_prefix("curl ")
        .and_then(|rest| rest.split_whitespace().next())
        .unwrap_or("N/A");

    let path = Command::new("which")
        .arg("curl")
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();

    if path.is_empty() {
        version.to_string()
    } else {
        format!("{version} => {path}")
    }
}

fn format_utc_timestamp(secs: u64) -> String {
    // Simple UTC formatting without pulling in chrono
    let days_since_epoch = secs / 86400;
    let time_of_day = secs % 86400;
    let hours = time_of_day / 3600;
    let minutes = (time_of_day % 3600) / 60;

    // Calculate date from days since epoch (1970-01-01)
    let (year, month, day) = days_to_ymd(days_since_epoch);
    let month_names = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    let month_name = month_names.get(month as usize - 1).unwrap_or(&"???");

    let _ = year;
    format!("{day:02} {month_name} {hours:02}:{minutes:02} UTC")
}

fn days_to_ymd(days: u64) -> (u64, u64, u64) {
    // Civil calendar algorithm
    let z = days + 719468;
    let era = z / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn format_utc_timestamp_produces_expected_format() {
        // 2026-03-23 15:42:00 UTC = 1774295120 seconds since epoch (approximately)
        let formatted = format_utc_timestamp(1774565520);
        assert!(formatted.contains("UTC"));
        assert!(formatted.contains(":"));
    }

    #[test]
    fn git_output_returns_na_for_empty_repo() {
        assert_eq!(git_output("", &["status"]), "N/A");
    }

    #[test]
    fn git_output_returns_na_for_nonexistent_path() {
        assert_eq!(git_output("/nonexistent/path", &["status"]), "N/A");
    }
}
