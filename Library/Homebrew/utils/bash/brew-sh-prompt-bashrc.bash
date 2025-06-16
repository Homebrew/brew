# Read the user's ~/.bashrc first
if [[ -f "${HOME}/.bashrc" ]]
then
  source "${HOME}/.bashrc"
fi

# Override the user's Bash prompt with our custom prompt
export PS1="\\[\\033[1;32m\\]${BREW_PROMPT_TYPE} \\[\\033[1;31m\\]\\w \\[\\033[1;34m\\]$\\[\\033[0m\\] "

# Add the Homebrew PATH in front of the user's PATH
export PATH="${BREW_PROMPT_PATH}:${PATH}"
unset BREW_PROMPT_TYPE BREW_PROMPT_PATH
