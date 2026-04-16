# typed: false
# frozen_string_literal: true

require "open3"

require "cmd/shared_examples/args_parse"
require "cmd/update"

RSpec.describe Homebrew::Cmd::Update do
  let(:update_script) { repository_root/"Library/Homebrew/cmd/update.sh" }
  let(:test_root) do
    (repository_root/"tmp").mkpath
    Pathname(Dir.mktmpdir("brew-update-", repository_root/"tmp"))
  end
  let(:repository_root) { Pathname(__dir__).parent.parent.parent.parent }

  after do
    FileUtils.rm_rf test_root
  end

  it_behaves_like "parseable arguments"

  def run_update_shell(script, env)
    Bundler.with_unbundled_env do
      Open3.capture3(env, "/bin/bash", "-c", script)
    end
  end

  it "passes all arguments through to delegated upgrades" do
    args_file = test_root/"brew-args.txt"
    brew_wrapper = test_root/"brew-wrapper"
    (test_root/"Library/Homebrew/utils").mkpath
    FileUtils.ln_s repository_root/"Library/Homebrew/utils/lock.sh", test_root/"Library/Homebrew/utils/lock.sh"
    brew_wrapper.write <<~SH
      #!/bin/bash
      printf '%s\n' "$@" > "#{args_file}"
    SH
    brew_wrapper.chmod 0755

    _stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        opoo() { echo "Warning: $*" >&2; }
        homebrew-update testball --auto-update --merge
      SH
      {
        "HOMEBREW_BREW_FILE" => brew_wrapper.to_s,
        "HOMEBREW_LIBRARY"   => (test_root/"Library").to_s,
      },
    )

    expect(status.success?).to be true
    expect(stderr).to eq(
      "Warning: Use `brew upgrade testball --auto-update --merge` to upgrade formulae; running it instead.\n",
    )
    expect(args_file.read).to eq("upgrade\ntestball\n--auto-update\n--merge\n")
  end

  it "passes `--auto-update` through to `update-report`" do
    args_file = test_root/"brew-args.txt"
    (test_root/"Library/Homebrew/utils").mkpath
    FileUtils.ln_s repository_root/"Library/Homebrew/utils/lock.sh", test_root/"Library/Homebrew/utils/lock.sh"
    (test_root/"cache").mkpath
    (test_root/"repository").mkpath

    _stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        brew() { printf '%s\n' "$@" > "#{args_file}"; }
        fetch_api_file() { :; }
        git_init_if_necessary() { :; }
        git() {
          [[ "$1" == "--version" ]] && return 0
          return 1
        }
        lock() { :; }
        odie() { echo "Error: $*" >&2; exit 1; }
        ohai() { :; }
        onoe() { echo "Error: $*" >&2; }
        safe_cd() { cd "$1" >/dev/null || exit 1; }
        setup_ca_certificates() { :; }
        setup_curl() { :; }
        setup_git() { :; }
        homebrew-update --auto-update
      SH
      {
        "HOMEBREW_CACHE"               => (test_root/"cache").to_s,
        "HOMEBREW_CELLAR"              => (test_root/"cellar").to_s,
        "HOMEBREW_LIBRARY"             => (test_root/"Library").to_s,
        "HOMEBREW_NO_INSTALL_FROM_API" => "1",
        "HOMEBREW_PREFIX"              => (test_root/"prefix").to_s,
        "HOMEBREW_REPOSITORY"          => (test_root/"repository").to_s,
      },
    )

    expect(status.success?).to be true
    expect(stderr).to be_empty
    expect(args_file.read).to eq("update-report\n--auto-update\n")
  end
end
