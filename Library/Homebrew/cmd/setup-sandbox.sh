# Documentation defined in Library/Homebrew/cmd/setup-sandbox.rb

# This Bubblewrap installation mirrors the package manager approaches in
# https://github.com/Homebrew/install and the Homebrew formula fallback in
# `ensure_sandbox_installed!` in Library/Homebrew/extend/os/linux/sandbox.rb.

# `sudo` strips `GITHUB_ACTIONS`, so also detect the runner via `/proc/1/cgroup`
# like `check-run-command-as-root` in Library/Homebrew/brew.sh does.
homebrew-on-github-actions() {
  [[ -n "${GITHUB_ACTIONS}" ]] && return 0
  grep -q "actions_job" /proc/1/cgroup &>/dev/null
}

homebrew-setup-sandbox() {
  # The sandbox sysctls and Bubblewrap are Linux-only.
  [[ -z "${HOMEBREW_LINUX}" ]] && return 0

  if homebrew-on-github-actions && ! command -v bwrap &>/dev/null
  then
    if command -v apt-get &>/dev/null
    then
      apt-get install --yes bubblewrap
    elif command -v dnf &>/dev/null
    then
      dnf install --assumeyes bubblewrap
    elif command -v yum &>/dev/null
    then
      yum install --assumeyes bubblewrap
    elif command -v pacman &>/dev/null
    then
      pacman --sync --noconfirm bubblewrap
    elif command -v apk &>/dev/null
    then
      apk add bubblewrap
    fi
  fi

  # These settings mirror SANDBOX_SYSCTL_SETTINGS in
  # Library/Homebrew/extend/os/linux/sandbox.rb; keep both in sync.
  local proc_sys_root="${HOMEBREW_PROC_SYS:-/proc/sys}"
  local sysctl_value
  local unprivileged_userns_clone_sysctl="${proc_sys_root}/kernel/unprivileged_userns_clone"
  if [[ -e "${unprivileged_userns_clone_sysctl}" ]] &&
     sysctl_value="$(sysctl -n "kernel.unprivileged_userns_clone")" &&
     [[ "${sysctl_value}" != "1" ]] &&
     [[ -w "${unprivileged_userns_clone_sysctl}" ]]
  then
    sysctl -w kernel.unprivileged_userns_clone=1 || true
  fi
  local max_user_namespaces_sysctl="${proc_sys_root}/user/max_user_namespaces"
  if [[ -e "${max_user_namespaces_sysctl}" ]] &&
     sysctl_value="$(sysctl -n "user.max_user_namespaces")" &&
     [[ "${sysctl_value}" -lt 28633 ]] &&
     [[ -w "${max_user_namespaces_sysctl}" ]]
  then
    sysctl -w user.max_user_namespaces=28633 || true
  fi

  local apparmor_restrict_unprivileged_userns_sysctl="${proc_sys_root}/kernel/apparmor_restrict_unprivileged_userns"
  if [[ -e "${apparmor_restrict_unprivileged_userns_sysctl}" ]] &&
     sysctl_value="$(sysctl -n "kernel.apparmor_restrict_unprivileged_userns")" &&
     [[ "${sysctl_value}" != "0" ]] &&
     [[ -w "${apparmor_restrict_unprivileged_userns_sysctl}" ]]
  then
    sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true
  fi
}
