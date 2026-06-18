# typed: true
# frozen_string_literal: true

require "open3"

require "cmd/shared_examples/args_parse"
require "cmd/setup-sandbox"

RSpec.describe Homebrew::Cmd::SetupSandbox do
  let(:setup_sandbox_script) { HOMEBREW_LIBRARY_PATH/"cmd/setup-sandbox.sh" }

  it_behaves_like "parseable arguments"

  def run_setup_sandbox_shell(script, env = {})
    Bundler.with_unbundled_env do
      Open3.capture3({ "GITHUB_ACTIONS" => nil, "HOMEBREW_LINUX" => "1" }.merge(env), "/bin/bash", "-c", script)
    end
  end

  it "does nothing on non-Linux systems" do
    stdout, _stderr, status = run_setup_sandbox_shell(<<~SH, "HOMEBREW_LINUX" => nil)
      source "#{setup_sandbox_script}"
      sysctl() { printf 'sysctl %s\\n' "$*"; }
      homebrew-setup-sandbox
    SH

    expect(status.success?).to be true
    expect(stdout).to be_empty
  end

  it "applies the sandbox sysctl settings when they are unset" do
    stdout, _stderr, status = run_setup_sandbox_shell <<~SH
      source "#{setup_sandbox_script}"
      sysctl() { [[ "$1" == "-n" ]] && { echo 0; return; }; printf 'sysctl %s\\n' "$*"; }
      homebrew-setup-sandbox
    SH

    expect(status.success?).to be true
    expect(stdout).to eq(<<~EOS)
      sysctl -w kernel.unprivileged_userns_clone=1
      sysctl -w user.max_user_namespaces=28633
    EOS
  end

  it "leaves already-configured sysctls unchanged" do
    stdout, _stderr, status = run_setup_sandbox_shell <<~SH
      source "#{setup_sandbox_script}"
      sysctl() {
        if [[ "$1" == "-n" ]]
        then
          case "$2" in
            kernel.unprivileged_userns_clone) echo 1;;
            user.max_user_namespaces) echo 28633;;
            kernel.apparmor_restrict_unprivileged_userns) echo 0;;
          esac
          return
        fi
        printf 'sysctl %s\\n' "$*"
      }
      homebrew-setup-sandbox
    SH

    expect(status.success?).to be true
    expect(stdout).to be_empty
  end

  it "installs Bubblewrap on GitHub Actions when it is missing" do
    stdout, _stderr, status = run_setup_sandbox_shell(<<~SH, "GITHUB_ACTIONS" => "true")
      source "#{setup_sandbox_script}"
      command() { case "$2" in bwrap) return 1;; apt-get) return 0;; *) return 1;; esac; }
      apt-get() { printf 'apt-get %s\\n' "$*"; }
      sysctl() { [[ "$1" == "-n" ]] && { echo 1; return; }; :; }
      homebrew-setup-sandbox
    SH

    expect(status.success?).to be true
    expect(stdout).to eq("apt-get install --yes bubblewrap\n")
  end

  it "does not install Bubblewrap when it is already present" do
    stdout, _stderr, status = run_setup_sandbox_shell(<<~SH, "GITHUB_ACTIONS" => "true")
      source "#{setup_sandbox_script}"
      command() { return 0; }
      apt-get() { printf 'apt-get %s\\n' "$*"; }
      sysctl() { [[ "$1" == "-n" ]] && { echo 1; return; }; :; }
      homebrew-setup-sandbox
    SH

    expect(status.success?).to be true
    expect(stdout).not_to include("apt-get")
  end

  it "installs Bubblewrap when only the cgroup marks a GitHub Actions runner" do
    stdout, _stderr, status = run_setup_sandbox_shell <<~SH
      source "#{setup_sandbox_script}"
      grep() { return 0; }
      command() { case "$2" in bwrap) return 1;; apt-get) return 0;; *) return 1;; esac; }
      apt-get() { printf 'apt-get %s\\n' "$*"; }
      sysctl() { [[ "$1" == "-n" ]] && { echo 1; return; }; :; }
      homebrew-setup-sandbox
    SH

    expect(status.success?).to be true
    expect(stdout).to eq("apt-get install --yes bubblewrap\n")
  end

  it "does not install Bubblewrap outside GitHub Actions" do
    stdout, _stderr, status = run_setup_sandbox_shell <<~SH
      source "#{setup_sandbox_script}"
      grep() { return 1; }
      apt-get() { printf 'apt-get %s\\n' "$*"; }
      sysctl() { [[ "$1" == "-n" ]] && { echo 1; return; }; :; }
      homebrew-setup-sandbox
    SH

    expect(status.success?).to be true
    expect(stdout).not_to include("apt-get")
  end
end
