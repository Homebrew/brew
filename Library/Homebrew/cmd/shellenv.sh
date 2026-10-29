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
    nu | -nu | nushell)
      # Nushell has no `eval` but NUON can be loaded immediately with `from nuon | load-env`
      # so later lines of `env.nu` can use Homebrew.
      # HOMEBREW_MANPATH and HOMEBREW_INFOPATH are the user's MANPATH and INFOPATH, passed through by bin/brew.
      # Values are raw strings, which need no escaping (unlike `"` strings, whose escaping varies with Bash 3.2),
      # closed by more `#`s than follow any `'` or start any value.
      local manpath="${HOMEBREW_MANPATH:-}" infopath="${HOMEBREW_PREFIX}/share/info:${HOMEBREW_INFOPATH:-}"
      local hashes="#" path_rest="${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:${HOMEBREW_PATH}:" nuon_path
      while [[ ":${HOMEBREW_PREFIX}:${HOMEBREW_CELLAR}:${HOMEBREW_REPOSITORY}:${HOMEBREW_PATH}:${manpath}:${infopath}" == *[:\']"${hashes}"* ]]
      do
        hashes+="#"
      done
      local raw_open="r${hashes}'" raw_close="'${hashes}"
      while [[ -n "${path_rest}" ]]
      do
        nuon_path+=" ${raw_open}${path_rest%%:*}${raw_close}"
        path_rest="${path_rest#*:}"
      done
      echo "{"
      echo "  HOMEBREW_PREFIX: ${raw_open}${HOMEBREW_PREFIX}${raw_close}"
      echo "  HOMEBREW_CELLAR: ${raw_open}${HOMEBREW_CELLAR}${raw_close}"
      echo "  HOMEBREW_REPOSITORY: ${raw_open}${HOMEBREW_REPOSITORY}${raw_close}"
      echo "  PATH: [${nuon_path# }]"
      if [[ -n "${manpath}" ]]
      then
        manpath="${manpath%"${manpath##*[!:]}"}"
        echo "  MANPATH: ${raw_open}:${manpath#"${manpath%%[!:]*}"}${raw_close}"
      fi
      echo "  INFOPATH: ${raw_open}${infopath}${raw_close}"
      echo "}"
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
