# typed: true
# frozen_string_literal: true

require "open3"
require "cmd/shared_examples/args_parse"
require "cmd/shared_examples/as_user"
require "cmd/as-brew-user"

RSpec.describe Homebrew::Cmd::AsBrewUser do
  let(:as_brew_user_script) { HOMEBREW_LIBRARY_PATH/"cmd/as-brew-user.sh" }
  let(:test_root) { mktmpdir }
  let(:macos_env) do
    {
      "HOMEBREW_BREW_FILE" => "brew",
      "HOMEBREW_LIBRARY"   => HOMEBREW_LIBRARY_PATH.parent.to_s,
      "HOMEBREW_MACOS"     => "1",
    }
  end

  sig { params(script: String, env: T::Hash[String, String]).returns([String, String, Process::Status]) }
  def run_as_brew_user_shell(script, env = {})
    Bundler.with_unbundled_env do
      Open3.capture3(env, "/bin/bash", "-c", script)
    end
  end

  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "as-brew-user", shell: true
  it_behaves_like "switching users without sudo", "as-brew-user"
  it_behaves_like "switching users without sudo", "as-brew-user" do
    sig { returns(T::Boolean) }
    let(:macos) { false }
  end

  it "selects the prefix owner instead of the console user" do
    stdout, = run_as_brew_user_shell(
      <<~SH,
        source "#{as_brew_user_script}"
        stat() { [[ "$*" == '-L -f %Su /opt/homebrew' ]] && echo brewer; }
        id() {
          [[ "$1" == -un ]] && { echo operator; return; }
          printf 'brewer:*:503:20::0:0:Brewer:#{test_root}:/bin/zsh\\n'
        }
        sudo() { printf '%s\\n' "$1 $2 $3"; }
        homebrew-as-brew-user upgrade
      SH
      macos_env.merge("HOMEBREW_PREFIX" => "/opt/homebrew"),
    )

    expect(stdout).to eq("-H -u brewer\n")
  end

  it "runs directly as the prefix owner without sudo" do
    brew_file = test_root/"brew"
    brew_file.write "#!/bin/bash\nprintf '%s\\n' \"$USER|$HOME|$*|$HOMEBREW_NO_SUDO\"\n"
    brew_file.chmod(0755)
    stdout, = run_as_brew_user_shell(
      <<~SH,
        source "#{as_brew_user_script}"
        stat() { echo brewer; }
        id() {
          [[ "$1" == -un ]] && { echo brewer; return; }
          printf 'brewer:*:503:20::0:0:Brewer:#{test_root}:/bin/zsh\\n'
        }
        sudo() { echo unexpected-sudo; exit 1; }
        homebrew-as-brew-user list
      SH
      macos_env.merge("HOMEBREW_PREFIX" => "/opt/homebrew", "HOMEBREW_NO_SUDO" => "1",
                      "HOMEBREW_BREW_FILE" => brew_file.to_s),
    )

    expect(stdout).to eq("brewer|#{test_root}|list|1\n")
  end

  it "rejects a root-owned prefix" do
    _, stderr, = run_as_brew_user_shell(
      <<~SH,
        source "#{as_brew_user_script}"
        stat() { echo root; }
        homebrew-as-brew-user install wget
      SH
      macos_env.merge("HOMEBREW_PREFIX" => "/opt/homebrew"),
    )

    expect(stderr).to include("The Homebrew prefix owner must not be root.")
  end

  it "enters the owner's home after switching users" do
    brew_file = test_root/"brew"
    brew_file.write "#!/bin/bash\nprintf '%s\\n' \"$PWD\"\n"
    brew_file.chmod(0755)
    stdout, = run_as_brew_user_shell(
      <<~SH,
        source "#{as_brew_user_script}"
        stat() { echo brewer; }
        id() {
          [[ "$1" == -un ]] && { echo operator; return; }
          printf 'brewer:*:503:20::0:0:Brewer:#{test_root}:/bin/zsh\\n'
        }
        cd() { return 1; }
        sudo() { shift 3; "$@"; }
        homebrew-as-brew-user list
      SH
      macos_env.merge("HOMEBREW_PREFIX" => "/opt/homebrew", "HOMEBREW_BREW_FILE" => brew_file.to_s),
    )

    expect(stdout).to eq("#{test_root}\n")
  end

  it "selects the prefix owner on Linux" do
    stdout, = run_as_brew_user_shell(
      <<~SH,
        source "#{as_brew_user_script}"
        stat() { [[ "$*" == '-L -c %U /home/linuxbrew/.linuxbrew' ]] && echo brewer; }
        id() { echo operator; }
        getent() { printf 'brewer:x:1001:1001:Brewer:#{test_root}:/bin/bash\\n'; }
        sudo() { printf '%s\\n' "$1 $2 $3"; }
        homebrew-as-brew-user upgrade
      SH
      macos_env.merge("HOMEBREW_MACOS" => "", "HOMEBREW_PREFIX" => "/home/linuxbrew/.linuxbrew"),
    )

    expect(stdout).to eq("-H -u brewer\n")
  end

  it "refuses to switch accounts when sudo is disabled" do
    stdout, stderr, = run_as_brew_user_shell(
      <<~SH,
        source "#{as_brew_user_script}"
        stat() { echo brewer; }
        id() {
          [[ "$1" == -un ]] && { echo operator; return; }
          printf 'brewer:*:503:20::0:0:Brewer:#{test_root}:/bin/zsh\\n'
        }
        sudo() { echo unexpected-sudo; }
        homebrew-as-brew-user upgrade
      SH
      macos_env.merge("HOMEBREW_PREFIX" => "/opt/homebrew", "HOMEBREW_NO_SUDO" => "1"),
    )

    expect([stdout, stderr]).to eq([
      "",
      "Error: Cannot switch to brewer with sudo disabled. Log in as brewer instead.\n",
    ])
  end
end
