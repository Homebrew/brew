# Documentation defined in Library/DinrusBrew/cmd/shellenv.rb

# DINRUSBREW_CELLAR and DINRUSBREW_PREFIX are set by extend/ENV/super.rb
# DINRUSBREW_REPOSITORY is set by bin/brew
# Leading colon in MANPATH prepends default man dirs to search path in Linux and macOS.
# Please do not submit PRs to remove it!
# shellcheck disable=SC2154
homebrew-shellenv() {
  if [[ "${DINRUSBREW_PATH%%:"${DINRUSBREW_PREFIX}"/sbin*}" == "${DINRUSBREW_PREFIX}/bin" ]]
  then
    return
  fi

  if [[ -n "$1" ]]
  then
    DINRUSBREW_SHELL_NAME="$1"
  else
    DINRUSBREW_SHELL_NAME="$(/bin/ps -p "${PPID}" -c -o comm=)"
  fi

  if [[ -n "${DINRUSBREW_MACOS}" ]] &&
     [[ "${DINRUSBREW_MACOS_VERSION_NUMERIC}" -ge "140000" ]] &&
     [[ -x /usr/libexec/path_helper ]]
  then
    DINRUSBREW_PATHS_FILE="${DINRUSBREW_PREFIX}/etc/paths"

    if [[ ! -f "${DINRUSBREW_PATHS_FILE}" ]]
    then
      printf '%s/bin\n%s/sbin\n' "${DINRUSBREW_PREFIX}" "${DINRUSBREW_PREFIX}" 2>/dev/null >"${DINRUSBREW_PATHS_FILE}"
    fi

    if [[ -r "${DINRUSBREW_PATHS_FILE}" ]]
    then
      PATH_HELPER_ROOT="${DINRUSBREW_PREFIX}"
    fi
  fi

  case "${DINRUSBREW_SHELL_NAME}" in
    fish | -fish)
      echo "set --global --export DINRUSBREW_PREFIX \"${DINRUSBREW_PREFIX}\";"
      echo "set --global --export DINRUSBREW_CELLAR \"${DINRUSBREW_CELLAR}\";"
      echo "set --global --export DINRUSBREW_REPOSITORY \"${DINRUSBREW_REPOSITORY}\";"
      echo "fish_add_path --global --move --path \"${DINRUSBREW_PREFIX}/bin\" \"${DINRUSBREW_PREFIX}/sbin\";"
      echo "if test -n \"\$MANPATH[1]\"; set --global --export MANPATH '' \$MANPATH; end;"
      echo "if not contains \"${DINRUSBREW_PREFIX}/share/info\" \$INFOPATH; set --global --export INFOPATH \"${DINRUSBREW_PREFIX}/share/info\" \$INFOPATH; end;"
      ;;
    csh | -csh | tcsh | -tcsh)
      echo "setenv DINRUSBREW_PREFIX ${DINRUSBREW_PREFIX};"
      echo "setenv DINRUSBREW_CELLAR ${DINRUSBREW_CELLAR};"
      echo "setenv DINRUSBREW_REPOSITORY ${DINRUSBREW_REPOSITORY};"
      if [[ -n "${PATH_HELPER_ROOT}" ]]
      then
        PATH_HELPER_ROOT="${PATH_HELPER_ROOT}" PATH="${DINRUSBREW_PATH}" /usr/libexec/path_helper -c
      else
        echo "setenv PATH ${DINRUSBREW_PREFIX}/bin:${DINRUSBREW_PREFIX}/sbin:\$PATH;"
      fi
      echo "test \${?MANPATH} -eq 1 && setenv MANPATH :\${MANPATH};"
      echo "setenv INFOPATH ${DINRUSBREW_PREFIX}/share/info\`test \${?INFOPATH} -eq 1 && echo :\${INFOPATH}\`;"
      ;;
    pwsh | -pwsh | pwsh-preview | -pwsh-preview)
      echo "[System.Environment]::SetEnvironmentVariable('DINRUSBREW_PREFIX','${DINRUSBREW_PREFIX}',[System.EnvironmentVariableTarget]::Process)"
      echo "[System.Environment]::SetEnvironmentVariable('DINRUSBREW_CELLAR','${DINRUSBREW_CELLAR}',[System.EnvironmentVariableTarget]::Process)"
      echo "[System.Environment]::SetEnvironmentVariable('DINRUSBREW_REPOSITORY','${DINRUSBREW_REPOSITORY}',[System.EnvironmentVariableTarget]::Process)"
      echo "[System.Environment]::SetEnvironmentVariable('PATH',\$('${DINRUSBREW_PREFIX}/bin:${DINRUSBREW_PREFIX}/sbin:'+\$ENV:PATH),[System.EnvironmentVariableTarget]::Process)"
      echo "[System.Environment]::SetEnvironmentVariable('MANPATH',\$('${DINRUSBREW_PREFIX}/share/man'+\$(if(\${ENV:MANPATH}){':'+\${ENV:MANPATH}})+':'),[System.EnvironmentVariableTarget]::Process)"
      echo "[System.Environment]::SetEnvironmentVariable('INFOPATH',\$('${DINRUSBREW_PREFIX}/share/info'+\$(if(\${ENV:INFOPATH}){':'+\${ENV:INFOPATH}})),[System.EnvironmentVariableTarget]::Process)"
      ;;
    *)
      echo "export DINRUSBREW_PREFIX=\"${DINRUSBREW_PREFIX}\";"
      echo "export DINRUSBREW_CELLAR=\"${DINRUSBREW_CELLAR}\";"
      echo "export DINRUSBREW_REPOSITORY=\"${DINRUSBREW_REPOSITORY}\";"
      if [[ "${DINRUSBREW_SHELL_NAME}" == "zsh" ]] || [[ "${DINRUSBREW_SHELL_NAME}" == "-zsh" ]]
      then
        echo "fpath[1,0]=\"${DINRUSBREW_PREFIX}/share/zsh/site-functions\";"
      fi
      if [[ -n "${PATH_HELPER_ROOT}" ]]
      then
        PATH_HELPER_ROOT="${PATH_HELPER_ROOT}" PATH="${DINRUSBREW_PATH}" /usr/libexec/path_helper -s
      else
        echo "export PATH=\"${DINRUSBREW_PREFIX}/bin:${DINRUSBREW_PREFIX}/sbin\${PATH+:\$PATH}\";"
      fi
      echo "[ -z \"\${MANPATH-}\" ] || export MANPATH=\":\${MANPATH#:}\";"
      echo "export INFOPATH=\"${DINRUSBREW_PREFIX}/share/info:\${INFOPATH:-}\";"
      ;;
  esac
}
