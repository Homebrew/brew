---
last_review_date: "2026-07-18"
---

# Command Not Found

Homebrew can suggest a formula when an interactive shell cannot find a command.
The handler queries `brew which-formula --explain` and prints an installation command when Homebrew knows which formula provides the missing executable.

## Setup

Run this command in an interactive Bash, fish or zsh session to print the setup instructions for that shell:

```sh
brew command-not-found-init
```

For Bash or zsh, add the printed handler-loading block to the startup file identified by the command.
For fish, add its block to `~/.config/fish/config.fish`.

The setup loads the handler from the current Homebrew repository, so it remains in sync when Homebrew updates.
Do not copy the handler implementation into a shell configuration file.

## Behaviour

When a command is missing, the handler searches Homebrew's formula metadata for an executable with the same name.
For example, a match can produce output similar to:

```console
$ example-command
The program 'example-command' is currently not installed. You can install it by typing:
  brew install example-formula
```

If Homebrew finds no match, the shell prints its normal command-not-found error.
The handler does not install software automatically.
