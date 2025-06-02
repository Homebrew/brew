#:  * `help`
#:
#:  Outputs the usage instructions for `brew`.
#:

# NOTE: Keep the length of vanilla `--help` less than 25 lines!
#       This is because the default Terminal height is 25 lines. Scrolling sucks
#       and concision is important. If more help is needed we should start
#       specialising help like the gem command does.
# NOTE: Keep lines less than 80 characters! Wrapping is just not cricket.
DINRUSBREW_HELP_MESSAGE=$(
  cat <<'EOS'
Пример использования:
  brew search TEXT|/REGEX/
  brew info [FORMULA|CASK...]
  brew install FORMULA|CASK...
  brew update
  brew upgrade [FORMULA|CASK...]
  brew uninstall FORMULA|CASK...
  brew list [FORMULA|CASK...]

Решение проблем:
  brew config
  brew doctor
  brew install --verbose --debug FORMULA|CASK

Внесение вклада:
  brew create URL [--no-fetch]
  brew edit [FORMULA|CASK...]

Дальнейшая помощь:
  brew commands
  brew help [COMMAND]
  man brew
  https://docs.brew.sh
EOS
)

homebrew-help() {
  if [[ -z "$*" ]]
  then
    echo "${DINRUSBREW_HELP_MESSAGE}" >&2
    exit 1
  fi

  echo "${DINRUSBREW_HELP_MESSAGE}"
  return 0
}
