---
last_review_date: "2026-07-18"
---

# `brew` Shell Completion

Homebrew provides completion definitions for `brew` in Bash, fish and zsh.
Some formulae and external commands provide completions for their own commands.

Homebrew stores completions under `HOMEBREW_PREFIX`, which a system shell may not search automatically.
The installer does not modify every shell's completion configuration because startup files and plugin managers vary.

Completions supplied by external Homebrew commands are not linked automatically.
Enable them with:

```sh
brew completions link
```

## Bash

Add the following to `~/.bash_profile`, or to `~/.profile` when `~/.bash_profile` does not exist:

```sh
if type brew &>/dev/null
then
  HOMEBREW_PREFIX="$(brew --prefix)"
  if [[ -r "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh" ]]
  then
    source "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh"
  else
    for COMPLETION in "${HOMEBREW_PREFIX}/etc/bash_completion.d/"*
    do
      [[ -r "${COMPLETION}" ]] && source "${COMPLETION}"
    done
  fi
fi
```

The `bash-completion` formula supports the system Bash shipped by macOS.
Use `bash-completion@2` with Homebrew's Bash 4 or newer.
The two formulae conflict with each other, so install only one.
The snippet above loads the installed version, so do not also source it elsewhere in the same shell configuration.

## zsh

`brew shellenv` adds Homebrew's zsh completion directory to `FPATH`.
Ensure that `eval "$(brew shellenv)"` runs before zsh initialises completion, then add the following to `~/.zshrc` if your configuration or framework does not already call `compinit`:

```sh
autoload -Uz compinit
compinit
```

Oh My Zsh calls `compinit` when it loads.
Make sure `brew shellenv` is evaluated first, particularly on Linux.

If zsh reports insecure completion directories, run `compaudit` to list the affected paths.
Inspect their ownership and remove group or world write access only from the directories reported by `compaudit`.
Do not recursively change permissions across the entire Homebrew prefix.

## fish

Homebrew's `fish` formula discovers Homebrew-managed completions automatically.

For a fish installation from another source, add the following to `~/.config/fish/config.fish`:

```fish
if test -d (brew --prefix)"/share/fish/completions"
    set -p fish_complete_path (brew --prefix)/share/fish/completions
end

if test -d (brew --prefix)"/share/fish/vendor_completions.d"
    set -p fish_complete_path (brew --prefix)/share/fish/vendor_completions.d
end
```

## PowerShell

Some formulae install PowerShell completions for their own commands under Homebrew's PowerShell completion directory.
Homebrew does not currently provide a PowerShell completion definition for `brew` itself.

Add the following to your PowerShell profile, such as `~/.config/powershell/Microsoft.PowerShell_profile.ps1`:

```pwsh
if ((Get-Command brew -ErrorAction SilentlyContinue) -and (Test-Path ($completions = "$(brew --prefix)/share/pwsh/completions"))) {
  foreach ($f in Get-ChildItem -Path $completions -File) {
    . $f
  }
}
```
