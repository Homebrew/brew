# Command Not Found

This feature reproduces Ubuntu's `command-not-found` for Homebrew users on macOS.

On Ubuntu, when you try to use a command that doesn't exist locally but is
available through a package, Bash will suggest a command to install it.
Using this script, you can replicate this feature on macOS:

```console
$ when
The program 'when' is currently not installed. You can install it by typing:
  brew install when
```

## Install

Installation instructions for your shell can be viewed by running:

```bash
brew command-not-found-init
```

* **Bash and Zsh**: Add the following line to your `~/.bash_profile` (bash) or `~/.zshrc` (zsh):

    ```bash
    HOMEBREW_COMMAND_NOT_FOUND_HANDLER="$(brew --repository)/Library/Homebrew/command-not-found/handler.sh"
    if [ -f "$HOMEBREW_COMMAND_NOT_FOUND_HANDLER" ]; then
      source "$HOMEBREW_COMMAND_NOT_FOUND_HANDLER";
    fi
    ```

* **Fish**: Add the following line to your `~/.config/fish/config.fish`:

    ```fish
    set HOMEBREW_COMMAND_NOT_FOUND_HANDLER (brew --repository)/Library/Homebrew/command-not-found/handler.fish
    if test -f $HOMEBREW_COMMAND_NOT_FOUND_HANDLER
      source $HOMEBREW_COMMAND_NOT_FOUND_HANDLER
    end
    ```

## Requirements

This tool requires one of the following:

* [Zsh](https://www.zsh.org) (the default on macOS Catalina and above)
* [Bash](https://www.gnu.org/software/bash/) (version 4 and higher)
* [Fish](https://fishshell.com)

## How it works

The `handler.sh` script defines a `command_not_found_handle` function which is
used by Bash when you try a command that doesn't exist.
The function calls `brew which-formula --explain` on your command.
If it finds a match it will print installation instructions.
If not, you'll get an error as expected.
