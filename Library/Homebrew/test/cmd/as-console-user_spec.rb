# typed: true
# frozen_string_literal: true

require "open3"

require "cmd/shared_examples/args_parse"
require "cmd/shared_examples/as_user"
require "cmd/as-console-user"

RSpec.describe Homebrew::Cmd::AsConsoleUser do
  let(:as_console_user_script) { HOMEBREW_LIBRARY_PATH/"cmd/as-console-user.sh" }
  let(:repository_root) { HOMEBREW_LIBRARY_PATH.parent.parent }
  let(:test_root) { mktmpdir }
  let(:macos_user_script) { repository_root/"Library/Homebrew/utils/macos_user.sh" }

  let(:macos_env) do
    {
      "HOMEBREW_BREW_FILE" => "brew",
      "HOMEBREW_LIBRARY"   => (repository_root/"Library").to_s,
      "HOMEBREW_MACOS"     => "1",
    }
  end

  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "as-console-user", shell: true
  it_behaves_like "switching users without sudo", "as-console-user"

  def run_as_console_user_shell(script, env = {})
    Bundler.with_unbundled_env do
      Open3.capture3(env, "/bin/bash", "-c", script)
    end
  end

  it "prints help and fails when no command is provided" do
    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{as_console_user_script}"
        brew() { printf '%s\\n' "$*" >&2; }
        homebrew-as-console-user
      SH
      "HOMEBREW_BREW_FILE" => "brew",
      "HOMEBREW_LIBRARY"   => (repository_root/"Library").to_s,
    )

    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
    expect(stderr).to eq("help as-console-user\n")
  end

  it "rejects a root console user" do
    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{as_console_user_script}"
        odie() { echo "Error: $*" >&2; exit 1; }
        stat() { printf 'root\\n'; }
        homebrew-as-console-user install wget
      SH
      macos_env,
    )

    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
    expect(stderr).to eq("Error: No supported macOS console user is logged in.\n")
  end

  it "rejects a loginwindow console user" do
    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{as_console_user_script}"
        odie() { echo "Error: $*" >&2; exit 1; }
        stat() { printf 'loginwindow\\n'; }
        homebrew-as-console-user install wget
      SH
      macos_env,
    )

    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
    expect(stderr).to eq("Error: No supported macOS console user is logged in.\n")
  end

  it "rejects non-macOS systems" do
    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{as_console_user_script}"
        odie() { echo "Error: $*" >&2; exit 1; }
        homebrew-as-console-user install wget
      SH
      "HOMEBREW_BREW_FILE" => "brew",
      "HOMEBREW_LIBRARY"   => (repository_root/"Library").to_s,
    )

    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
    expect(stderr).to eq("Error: `brew as-console-user` is only supported on macOS.\n")
  end

  it "rejects an invalid exit status from login" do
    _, _, status = run_as_console_user_shell <<~SH
      source "#{macos_user_script}"
      chown() { :; }
      login() { printf '256\\n' >"$9"; }
      homebrew-login brewer true
    SH

    expect(status.exitstatus).to eq 1
  end

  it "uses the package user plist before the console user" do
    homebrew_pkg_user_plist = test_root/".homebrew_pkg_user.plist"
    homebrew_pkg_user_plist.write "plist"

    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{macos_user_script}"
        plutil() { printf 'munki\\n'; }
        stat() { printf 'Regular File 0 600 1\\n'; }
        ls() { printf -- '-rw------- 1 root wheel 0 x\\n'; }
        homebrew-package-user
      SH
      "HOMEBREW_PKG_USER_PLIST" => homebrew_pkg_user_plist.to_s,
    )

    expect(status.success?).to be true
    expect(stdout).to eq("munki\n")
    expect(stderr).to be_empty
  end

  it "requires the package user plist to have a single link" do
    plist = test_root/"user.plist"
    plist.write "plist"

    stdout, _, status = run_as_console_user_shell(
      <<~SH,
        source "#{macos_user_script}"
        homebrew-console-user() { return 1; }
        stat() { echo 'Regular File 0 600 2'; }
        ls() { echo '-rw------- 2 root wheel'; }
        plutil() { echo managing-user; }
        homebrew-package-user
      SH
      "HOMEBREW_PKG_USER_PLIST" => plist.to_s,
    )

    expect([status.exitstatus, stdout]).to eq([1, ""])
  end

  it "honours a root-owned plist that carries extended attributes" do
    homebrew_pkg_user_plist = test_root/".homebrew_pkg_user.plist"
    homebrew_pkg_user_plist.write "plist"

    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{macos_user_script}"
        plutil() { printf 'munki\\n'; }
        stat() { printf 'Regular File 0 600 1\\n'; }
        ls() { printf -- '-rw-------@ 1 root wheel 0 x\\n'; }
        homebrew-package-user
      SH
      "HOMEBREW_PKG_USER_PLIST" => homebrew_pkg_user_plist.to_s,
    )

    expect(status.success?).to be true
    expect(stdout).to eq("munki\n")
    expect(stderr).to be_empty
  end

  it "ignores a package user plist not owned by root" do
    homebrew_pkg_user_plist = test_root/".homebrew_pkg_user.plist"
    homebrew_pkg_user_plist.write "plist"

    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{macos_user_script}"
        plutil() { printf 'attacker\\n'; }
        stat() { case "$*" in *"/dev/console") printf 'root\\n';; *) printf 'Regular File 502 600 1\\n';; esac; }
        ls() { printf -- '-rw------- 1 attacker staff 0 x\\n'; }
        homebrew-package-user
      SH
      "HOMEBREW_PKG_USER_PLIST" => homebrew_pkg_user_plist.to_s,
    )

    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
    expect(stderr).to be_empty
  end

  it "ignores a package user plist with loose permissions" do
    homebrew_pkg_user_plist = test_root/".homebrew_pkg_user.plist"
    homebrew_pkg_user_plist.write "plist"

    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{macos_user_script}"
        plutil() { printf 'attacker\\n'; }
        stat() { case "$*" in *"/dev/console") printf 'root\\n';; *) printf 'Regular File 0 644 1\\n';; esac; }
        ls() { printf -- '-rw-rw-rw- 1 root wheel 0 x\\n'; }
        homebrew-package-user
      SH
      "HOMEBREW_PKG_USER_PLIST" => homebrew_pkg_user_plist.to_s,
    )

    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
    expect(stderr).to be_empty
  end

  it "ignores a package user plist carrying an ACL" do
    homebrew_pkg_user_plist = test_root/".homebrew_pkg_user.plist"
    homebrew_pkg_user_plist.write "plist"

    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{macos_user_script}"
        plutil() { printf 'attacker\\n'; }
        stat() { case "$*" in *"/dev/console") printf 'root\\n';; *) printf 'Regular File 0 600 1\\n';; esac; }
        ls() { printf -- '-rw-------@ 1 root wheel 0 x\\n 0: group:everyone deny delete\\n'; }
        homebrew-package-user
      SH
      "HOMEBREW_PKG_USER_PLIST" => homebrew_pkg_user_plist.to_s,
    )

    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
    expect(stderr).to be_empty
  end

  it "ignores a package user plist that is a symlink" do
    homebrew_pkg_user_target = test_root/"target.plist"
    homebrew_pkg_user_target.write "plist"
    homebrew_pkg_user_plist = test_root/".homebrew_pkg_user.plist"
    FileUtils.ln_s homebrew_pkg_user_target, homebrew_pkg_user_plist

    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{macos_user_script}"
        plutil() { printf 'attacker\\n'; }
        stat() { case "$*" in *"/dev/console") printf 'root\\n';; *) printf 'root\\n';; esac; }
        ls() { printf -- '-rw------- 1 root wheel 0 x\\n'; }
        homebrew-package-user
      SH
      "HOMEBREW_PKG_USER_PLIST" => homebrew_pkg_user_plist.to_s,
    )

    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
    expect(stderr).to be_empty
  end

  it "falls back to the console user without a package user plist" do
    stdout, stderr, status = run_as_console_user_shell <<~SH
      source "#{macos_user_script}"
      stat() { printf 'mike\\n'; }
      homebrew-package-user
    SH

    expect(status.success?).to be true
    expect(stdout).to eq("mike\n")
    expect(stderr).to be_empty
  end

  it "rejects package user lookup without a package user or console user" do
    stdout, stderr, status = run_as_console_user_shell <<~SH
      source "#{macos_user_script}"
      stat() { printf 'root\\n'; }
      homebrew-package-user
    SH

    expect(status.exitstatus).to eq 1
    expect(stdout).to be_empty
    expect(stderr).to be_empty
  end

  it "dispatches the nested brew command as the console user" do
    args_file = test_root/"sudo-args.txt"
    console_home = test_root/"console-home"
    console_home.mkpath

    stdout, stderr, status = run_as_console_user_shell(
      <<~SH,
        source "#{as_console_user_script}"
        odie() { echo "Error: $*" >&2; exit 1; }
        stat() { printf 'mike\\n'; }
        id() {
          [[ "$1" == -un ]] && { echo operator; return; }
          printf 'mike:*:501:20::0:0:Mike:#{console_home}:/bin/zsh\\n'
        }
        sudo() {
          printf 'cwd=%s\\n' "$PWD" > "#{args_file}"
          printf '%s\\n' "$@" >> "#{args_file}"
          return 42
        }
        homebrew-as-console-user upgrade git --minimum-version=2.50.1
      SH
      macos_env.merge("HOMEBREW_BREW_FILE" => "/opt/homebrew/bin/brew", "HOMEBREW_SUDO_USER" => ""),
    )

    expect(status.exitstatus).to eq 42
    expect(stdout).to be_empty
    expect(stderr).to be_empty
    expect(args_file.read).to eq <<~EOS
      cwd=#{Dir.pwd}
      -H
      -u
      mike
      /usr/bin/env
      -i
      HOME=#{console_home}
      USER=mike
      LOGNAME=mike
      PWD=#{Dir.pwd}
      PATH=/usr/bin:/bin:/usr/sbin:/sbin
      SUDO_USER=operator
      /opt/homebrew/bin/brew
      upgrade
      git
      --minimum-version=2.50.1
    EOS
  end

  it "preserves sudo for the console command when it is available" do
    ENV.delete("HOMEBREW_NO_SUDO")
    stdout, = run_as_console_user_shell(
      <<~SH,
        source "#{as_console_user_script}"
        stat() { echo brewer; }
        id() {
          [[ "$1" == -un ]] && { echo brewer; return; }
          printf 'brewer:*:503:20::0:0:Brewer:#{test_root}:/bin/zsh\\n'
        }
        sudo() { printf '%s\\n' "$1 $2 $3"; }
        homebrew-as-console-user list
      SH
      macos_env,
    )

    expect(stdout).to eq("-H -u brewer\n")
  end
end
