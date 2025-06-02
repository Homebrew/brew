# Documentation defined in Library/DinrusBrew/cmd/setup-ruby.rb

# DINRUSBREW_LIBRARY is set by brew.sh
# DINRUSBREW_BREW_FILE is set by extend/ENV/super.rb
# shellcheck disable=SC2154
homebrew-setup-ruby() {
  source "${DINRUSBREW_LIBRARY}/DinrusBrew/utils/helpers.sh"
  source "${DINRUSBREW_LIBRARY}/DinrusBrew/utils/ruby.sh"
  setup-ruby-path

  if [[ -z "${DINRUSBREW_DEVELOPER}" ]]
  then
    return
  fi

  # Avoid running Bundler if the command doesn't need it.
  local command="$1"
  if [[ -n "${command}" ]]
  then
    source "${DINRUSBREW_LIBRARY}/DinrusBrew/command_path.sh"

    command_path="$(homebrew-command-path "${command}")"
    if [[ -n "${command_path}" ]]
    then
      if [[ "${command_path}" != *"/dev-cmd/"* ]]
      then
        return
      elif ! grep -q "DinrusBrew.install_bundler_gems\!" "${command_path}"
      then
        return
      fi
    fi
  fi

  setup-gem-home-bundle-gemfile

  if ! bundle check &>/dev/null
  then
    "${DINRUSBREW_BREW_FILE}" install-bundler-gems
  fi
}
