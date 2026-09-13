# Documentation defined in Library/Homebrew/cmd/shellenv.rb

# HOMEBREW_CELLAR and HOMEBREW_PREFIX are set by extend/ENV/super.rb
# HOMEBREW_REPOSITORY is set by bin/brew
# Leading colon in MANPATH prepends default man dirs to search path in Linux and macOS.
# Trailing colon in INFOPATH appends the default info dirs to the search path.
# Please do not submit PRs to remove it!
# shellcheck disable=SC2154
homebrew-shellenv() {
  if [[ "${HOMEBREW_PATH}:" == "${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:"* ]]
  then
    return
  fi

  # Use specified shell name parameter, if available.
  HOMEBREW_SHELL_NAME="${1:-}"

  # Use the parent process name, if possible.
  # This is known to fail under some sandboxes.
  if [[ -z "${HOMEBREW_SHELL_NAME}" ]]
  then
    HOMEBREW_SHELL_NAME="$(/bin/ps -p "${PPID}" -c -o comm= 2>/dev/null)"
  fi

  # Fall back to the (login) shell name from the environment.
  if [[ -z "${HOMEBREW_SHELL_NAME}" ]]
  then
    HOMEBREW_SHELL_NAME="${SHELL##*/}"
  fi

  case "${HOMEBREW_SHELL_NAME}" in
    fish | -fish)
      echo "set --global --export HOMEBREW_PREFIX \"${HOMEBREW_PREFIX}\";"
      echo "set --global --export HOMEBREW_CELLAR \"${HOMEBREW_CELLAR}\";"
      echo "set --global --export HOMEBREW_REPOSITORY \"${HOMEBREW_REPOSITORY}\";"
      echo "fish_add_path --global --move --path \"${HOMEBREW_PREFIX}/bin\" \"${HOMEBREW_PREFIX}/sbin\";"
      echo "if test -n \"\$MANPATH\"; set --global --export MANPATH (string replace --regex '^:*(.*?):*\$' ':\$1' -- \"\$MANPATH\"); end;"
      echo "if not set --query INFOPATH; set INFOPATH ''; end; set --global --export INFOPATH \"${HOMEBREW_PREFIX}/share/info\" \$INFOPATH;"
      ;;
    csh | -csh | tcsh | -tcsh)
      echo "setenv HOMEBREW_PREFIX ${HOMEBREW_PREFIX};"
      echo "setenv HOMEBREW_CELLAR ${HOMEBREW_CELLAR};"
      echo "setenv HOMEBREW_REPOSITORY ${HOMEBREW_REPOSITORY};"
      echo "setenv PATH \"${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:\$PATH\";"
      echo "test \${?MANPATH} -eq 1 && test -n \"\${MANPATH}\" && setenv MANPATH :\`printf '%s' \"\${MANPATH}\" | /usr/bin/sed -e 's/^:*//' -e 's/:*\$//'\`;"
      echo "test \${?INFOPATH} -eq 1 || setenv INFOPATH '';"
      echo "setenv INFOPATH \"${HOMEBREW_PREFIX}/share/info:\${INFOPATH}\";"
      ;;
    pwsh | -pwsh | pwsh-preview | -pwsh-preview)
      echo "[System.Environment]::SetEnvironmentVariable('HOMEBREW_PREFIX','${HOMEBREW_PREFIX}',[System.EnvironmentVariableTarget]::Process)"
      echo "[System.Environment]::SetEnvironmentVariable('HOMEBREW_CELLAR','${HOMEBREW_CELLAR}',[System.EnvironmentVariableTarget]::Process)"
      echo "[System.Environment]::SetEnvironmentVariable('HOMEBREW_REPOSITORY','${HOMEBREW_REPOSITORY}',[System.EnvironmentVariableTarget]::Process)"
      echo "[System.Environment]::SetEnvironmentVariable('PATH',\$('${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:'+\$ENV:PATH),[System.EnvironmentVariableTarget]::Process)"
      echo "if (\${ENV:MANPATH}) { [System.Environment]::SetEnvironmentVariable('MANPATH',(':'+\${ENV:MANPATH}.Trim(':')),[System.EnvironmentVariableTarget]::Process) }"
      echo "[System.Environment]::SetEnvironmentVariable('INFOPATH',('${HOMEBREW_PREFIX}/share/info:'+\${ENV:INFOPATH}),[System.EnvironmentVariableTarget]::Process)"
      ;;
    *)
      echo "export HOMEBREW_PREFIX=\"${HOMEBREW_PREFIX}\";"
      echo "export HOMEBREW_CELLAR=\"${HOMEBREW_CELLAR}\";"
      echo "export HOMEBREW_REPOSITORY=\"${HOMEBREW_REPOSITORY}\";"
      if [[ "${HOMEBREW_SHELL_NAME}" == "zsh" ]] || [[ "${HOMEBREW_SHELL_NAME}" == "-zsh" ]]
      then
        echo "fpath[1,0]=\"${HOMEBREW_PREFIX}/share/zsh/site-functions\";"
        echo "export FPATH;"
      fi
      echo "export PATH=\"${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin\${PATH+:\$PATH}\";"
      echo "[ -z \"\${MANPATH-}\" ] || { export MANPATH=\"\${MANPATH%\"\${MANPATH##*[!:]}\"}\"; export MANPATH=\":\${MANPATH#\"\${MANPATH%%[!:]*}\"}\"; };"
      echo "export INFOPATH=\"${HOMEBREW_PREFIX}/share/info:\${INFOPATH:-}\";"
      ;;
  esac
}
