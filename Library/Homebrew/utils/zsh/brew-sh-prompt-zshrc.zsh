# Read the user's ~/.zshrc first
if [[ -f "${HOME}/.zshrc" ]]
then
  source "${HOME}/.zshrc"
fi

# Override the user's ZSH prompt with our custom prompt
export PROMPT="%B%F{green}${BREW_PROMPT_TYPE}%f %F{blue}$%f%b "
export RPROMPT="[%B%F{red}%~%f%b]"

# Add the Homebrew PATH in front of the user's PATH
export PATH="${BREW_PROMPT_PATH}:${PATH}"
unset BREW_PROMPT_TYPE BREW_PROMPT_PATH
