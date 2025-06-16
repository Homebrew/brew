#:  * `help`
#:
#:  Outputs the usage instructions for `brew`.
#:

# NOTE: Keep the length of vanilla `--help` less than 25 lines!
#       This is because the default Terminal height is 25 lines. Scrolling sucks
#       and concision is important. If more help is needed we should start
#       specialising help like the gem command does.
# NOTE: Keep lines less than 80 characters! Wrapping is just not cricket.
HOMEBREW_HELP_MESSAGE=$(
  cat <<'EOS'
Example usage:
  brew search TEXT|/REGEX/
  brew info [FORMULA|CASK...]
  brew install FORMULA|CASK...
  brew update
  brew upgrade [FORMULA|CASK...]
  brew uninstall FORMULA|CASK...
  brew list [FORMULA|CASK...]

Troubleshooting:
  brew config
  brew doctor
  brew install --verbose --debug FORMULA|CASK

Contributing:
  brew create URL [--no-fetch]
  brew edit [FORMULA|CASK...]

Further help:
  brew commands
  brew help [COMMAND]
  man brew
  https://docs.brew.sh
EOS
)

homebrew-help() {
  if [[ -z "$*" ]]
  then
    echo "${HOMEBREW_HELP_MESSAGE}" >&2
    exit 1
  fi

  echo "${HOMEBREW_HELP_MESSAGE}"
  return 0
}
