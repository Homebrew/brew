# typed: true
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
  let(:repository_root) { Pathname(T.must(__dir__)).parent.parent.parent.parent }

  after do
    FileUtils.rm_rf test_root
  end

  it_behaves_like "parseable arguments"

  def run_update_shell(script, env)
    Bundler.with_unbundled_env do
      Open3.capture3(env, "/bin/bash", "-c", script)
    end
  end

  def setup_update_utils
    (test_root/"Library/Homebrew/utils").mkpath
    FileUtils.ln_s repository_root/"Library/Homebrew/utils.sh", test_root/"Library/Homebrew/utils.sh"
    %w[api cmd executables formatter lock tty].each do |name|
      FileUtils.ln_s repository_root/"Library/Homebrew/utils/#{name}.sh",
                     test_root/"Library/Homebrew/utils/#{name}.sh"
    end
  end

  it "passes all arguments through to delegated upgrades" do
    args_file = test_root/"brew-args.txt"
    brew_wrapper = test_root/"brew-wrapper"
    setup_update_utils
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
    setup_update_utils
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

  it "preserves `update-report` arguments and exit status with the Rust frontend enabled" do
    args_file = test_root/"brew-args.txt"
    brew_wrapper = test_root/"brew-wrapper"
    setup_update_utils
    (test_root/"cache").mkpath
    (test_root/"repository").mkpath
    brew_wrapper.write <<~SH
      #!/bin/bash
      printf '%s\n' "$@" > "#{args_file}"
      exit 42
    SH
    brew_wrapper.chmod 0755

    _stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{repository_root}/Library/Homebrew/utils.sh"
        source "#{update_script}"
        fetch_api_file() { :; }
        git() {
          [[ "$1" == "--version" ]] && return 0
          return 1
        }
        git_init_if_necessary() { :; }
        lock() { :; }
        setup_ca_certificates() { :; }
        setup_curl() { :; }
        setup_git() { :; }
        homebrew-update --auto-update
      SH
      {
        "HOMEBREW_BREW_FILE"                  => brew_wrapper.to_s,
        "HOMEBREW_CACHE"                      => (test_root/"cache").to_s,
        "HOMEBREW_CELLAR"                     => (test_root/"cellar").to_s,
        "HOMEBREW_EXPERIMENTAL_RUST_FRONTEND" => "1",
        "HOMEBREW_LIBRARY"                    => (test_root/"Library").to_s,
        "HOMEBREW_NO_INSTALL_FROM_API"        => "1",
        "HOMEBREW_PREFIX"                     => (test_root/"prefix").to_s,
        "HOMEBREW_REPOSITORY"                 => (test_root/"repository").to_s,
      },
    )

    expect(status.exitstatus).to eq 42
    expect(stderr).to be_empty
    expect(args_file.read).to eq("update-report\n--auto-update\n")
  end

  it "does not query redirected remote metadata for no-op tap updates" do
    args_file = test_root/"brew-args.txt"
    fetches_file = test_root/"fetches.txt"
    metadata_queries_file = test_root/"metadata-queries.txt"
    repository = test_root/"repository"
    tap_path = test_root/"Library/Taps/old/homebrew-foo"
    setup_update_utils
    (repository/".git").mkpath
    (tap_path/".git").mkpath
    (test_root/"cache").mkpath
    (test_root/"cache/all_commands_list.txt").write ""

    _stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        brew() { printf '%s\\n' "$@" > "#{args_file}"; return 1; }
        fetch_api_file() { :; }
        git_init_if_necessary() { :; }
        git() {
          case "$*" in
            "--version") return 0 ;;
            "config --local --get remote.origin.url" | "config remote.origin.url")
              if [[ "$PWD" == "#{tap_path}" ]]
              then
                echo "https://github.com/old/homebrew-foo"
              else
                echo "https://github.com/Homebrew/brew"
              fi
              return 0
              ;;
            "symbolic-ref refs/remotes/origin/HEAD")
              echo "refs/remotes/origin/main"
              return 0
              ;;
            "rev-parse refs/remotes/origin/main" | "rev-parse -q --verify refs/remotes/origin/main" | "rev-parse -q --verify HEAD")
              echo abc
              return 0
              ;;
            "tag --list")
              echo "4.0.0"
              return 0
              ;;
            fetch*)
              echo "$PWD" >> "#{fetches_file}"
              return 0
              ;;
          esac
          printf 'unexpected git %s\\n' "$*" >&2
          return 1
        }
        curl() {
          local url
          for url in "$@"; do :; done

          case "${url}" in
            "https://api.github.com/repos/Homebrew/brew/tags" | "https://api.github.com/repos/old/homebrew-foo/commits/main")
              printf '304 %s' "${url}"
              ;;
            "https://api.github.com/repos/Homebrew/brew" | "https://api.github.com/repos/old/homebrew-foo")
              echo "${url}" >> "#{metadata_queries_file}"
              printf 'unexpected metadata query\\n' >&2
              return 1
              ;;
            *)
              printf 'unexpected curl %s\\n' "${url}" >&2
              return 1
              ;;
          esac
        }
        lock() { :; }
        odie() { echo "Error: $*" >&2; exit 1; }
        ohai() { :; }
        onoe() { echo "Error: $*" >&2; }
        safe_cd() { cd "$1" &>/dev/null || exit 1; }
        setup_ca_certificates() { :; }
        setup_curl() { :; }
        setup_git() { :; }
        homebrew-update --auto-update
      SH
      {
        "HOMEBREW_BREW_DEFAULT_GIT_REMOTE" => "https://github.com/Homebrew/brew",
        "HOMEBREW_BREW_GIT_REMOTE"         => "https://github.com/Homebrew/brew",
        "HOMEBREW_CACHE"                   => (test_root/"cache").to_s,
        "HOMEBREW_CASK_REPOSITORY"         => (test_root/"cask").to_s,
        "HOMEBREW_CELLAR"                  => (test_root/"cellar").to_s,
        "HOMEBREW_CORE_DEFAULT_GIT_REMOTE" => "https://github.com/Homebrew/homebrew-core",
        "HOMEBREW_CORE_GIT_REMOTE"         => "https://github.com/Homebrew/homebrew-core",
        "HOMEBREW_CORE_REPOSITORY"         => (test_root/"core").to_s,
        "HOMEBREW_LIBRARY"                 => (test_root/"Library").to_s,
        "HOMEBREW_NO_ENV_HINTS"            => "1",
        "HOMEBREW_NO_INSTALL_FROM_API"     => "1",
        "HOMEBREW_PREFIX"                  => (test_root/"prefix").to_s,
        "HOMEBREW_REPOSITORY"              => repository.to_s,
        "HOMEBREW_USER_AGENT_CURL"         => "Homebrew/test",
      },
    )

    expect(status.success?).to be true
    expect(stderr).to be_empty
    expect(args_file).not_to exist
    expect(fetches_file).not_to exist
    expect(metadata_queries_file).not_to exist
  end

  it "treats redirected tap SHA API checks as updates" do
    args_file = test_root/"brew-args.txt"
    fetches_file = test_root/"fetches.txt"
    metadata_queries_file = test_root/"metadata-queries.txt"
    repository = test_root/"repository"
    tap_path = test_root/"Library/Taps/old/homebrew-foo"
    setup_update_utils
    (repository/".git").mkpath
    (tap_path/".git").mkpath
    (test_root/"cache").mkpath
    (test_root/"cache/all_commands_list.txt").write ""

    _stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        brew() { printf '%s\\n' "$@" > "#{args_file}"; }
        fetch_api_file() { :; }
        git_init_if_necessary() { :; }
        git() {
          case "$*" in
            "--version") return 0 ;;
            "config --local --get remote.origin.url" | "config remote.origin.url")
              if [[ "$PWD" == "#{tap_path}" ]]
              then
                echo "https://github.com/old/homebrew-foo"
              else
                echo "https://github.com/Homebrew/brew"
              fi
              return 0
              ;;
            "symbolic-ref refs/remotes/origin/HEAD")
              echo "refs/remotes/origin/main"
              return 0
              ;;
            "rev-parse refs/remotes/origin/main" | "rev-parse -q --verify refs/remotes/origin/main" | "rev-parse -q --verify HEAD")
              echo abc
              return 0
              ;;
            "tag --list")
              echo "4.0.0"
              return 0
              ;;
            "fetch --tags --force -q origin refs/heads/main:refs/remotes/origin/main")
              echo "$PWD" >> "#{fetches_file}"
              return 0
              ;;
          esac
          printf 'unexpected git %s\\n' "$*" >&2
          return 1
        }
        curl() {
          local url
          for url in "$@"; do :; done

          case "${url}" in
            "https://api.github.com/repos/Homebrew/brew/tags")
              printf '304 %s' "${url}"
              ;;
            "https://api.github.com/repos/old/homebrew-foo/commits/main")
              printf '304 https://api.github.com/repositories/456/commits/main'
              ;;
            "https://api.github.com/repos/Homebrew/brew")
              printf 'unexpected brew metadata query\\n' >&2
              return 1
              ;;
            "https://api.github.com/repos/old/homebrew-foo")
              echo "${url}" >> "#{metadata_queries_file}"
              printf '{\\n  "clone_url": "https://github.com/new/homebrew-foo.git",\\n  "html_url": "https://github.com/new/homebrew-foo"\\n}\\n'
              ;;
            *)
              printf 'unexpected curl %s\\n' "${url}" >&2
              return 1
              ;;
          esac
        }
        lock() { :; }
        odie() { echo "Error: $*" >&2; exit 1; }
        ohai() { :; }
        onoe() { echo "Error: $*" >&2; }
        safe_cd() { cd "$1" &>/dev/null || exit 1; }
        setup_ca_certificates() { :; }
        setup_curl() { :; }
        setup_git() { :; }
        homebrew-update --auto-update
      SH
      {
        "HOMEBREW_BREW_DEFAULT_GIT_REMOTE" => "https://github.com/Homebrew/brew",
        "HOMEBREW_BREW_GIT_REMOTE"         => "https://github.com/Homebrew/brew",
        "HOMEBREW_CACHE"                   => (test_root/"cache").to_s,
        "HOMEBREW_CASK_REPOSITORY"         => (test_root/"cask").to_s,
        "HOMEBREW_CELLAR"                  => (test_root/"cellar").to_s,
        "HOMEBREW_CORE_DEFAULT_GIT_REMOTE" => "https://github.com/Homebrew/homebrew-core",
        "HOMEBREW_CORE_GIT_REMOTE"         => "https://github.com/Homebrew/homebrew-core",
        "HOMEBREW_CORE_REPOSITORY"         => (test_root/"core").to_s,
        "HOMEBREW_LIBRARY"                 => (test_root/"Library").to_s,
        "HOMEBREW_NO_ENV_HINTS"            => "1",
        "HOMEBREW_NO_INSTALL_FROM_API"     => "1",
        "HOMEBREW_PREFIX"                  => (test_root/"prefix").to_s,
        "HOMEBREW_REPOSITORY"              => repository.to_s,
        "HOMEBREW_USER_AGENT_CURL"         => "Homebrew/test",
      },
    )

    expect(status.success?).to be true
    expect(stderr).to be_empty
    expect(args_file.read).to eq("update-report\n--auto-update\n")
    expect(fetches_file.read).to eq("#{tap_path}\n")
    expect((repository/".git/REDIRECTED_REMOTES").read).to eq(
      "#{tap_path}\thttps://github.com/new/homebrew-foo.git\n",
    )
    expect(metadata_queries_file.read).to eq("https://api.github.com/repos/old/homebrew-foo\n")
  end

  it "queries redirected remote metadata only for taps" do
    args_file = test_root/"brew-args.txt"
    metadata_queries_file = test_root/"metadata-queries.txt"
    repository = test_root/"repository"
    tap_path = test_root/"Library/Taps/old/homebrew-foo"
    setup_update_utils
    (repository/".git").mkpath
    (tap_path/".git").mkpath
    (test_root/"cache").mkpath
    (test_root/"cache/all_commands_list.txt").write ""

    _stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        brew() { printf '%s\\n' "$@" > "#{args_file}"; }
        fetch_api_file() { :; }
        git_init_if_necessary() { :; }
        git() {
          case "$*" in
            "--version") return 0 ;;
            "config --local --get remote.origin.url" | "config remote.origin.url")
              if [[ "$PWD" == "#{tap_path}" ]]
              then
                echo "https://github.com/old/homebrew-foo"
              else
                echo "https://github.com/Homebrew/brew"
              fi
              return 0
              ;;
            "symbolic-ref refs/remotes/origin/HEAD")
              echo "refs/remotes/origin/main"
              return 0
              ;;
            "rev-parse refs/remotes/origin/main" | "rev-parse -q --verify refs/remotes/origin/main" | "rev-parse -q --verify HEAD" | "rev-parse -q --verify main")
              echo abc
              return 0
              ;;
            "merge-base --is-ancestor abc abc")
              return 0
              ;;
            "tag --list")
              echo "4.0.0"
              return 0
              ;;
            "fetch --tags --force -q origin refs/heads/main:refs/remotes/origin/main")
              return 0
              ;;
          esac
          printf 'unexpected git %s\\n' "$*" >&2
          return 1
        }
        curl() {
          local url
          for url in "$@"; do :; done

          case "${url}" in
            "https://api.github.com/repos/Homebrew/brew/tags")
              printf 'unexpected brew API query\\n' >&2
              return 1
              ;;
            "https://api.github.com/repos/old/homebrew-foo/commits/main")
              printf '304 https://api.github.com/repositories/456/commits/main'
              ;;
            "https://api.github.com/repos/Homebrew/brew" | "https://api.github.com/repos/old/homebrew-foo")
              echo "${url}" >> "#{metadata_queries_file}"
              printf '{\\n  "clone_url": "https://github.com/new/homebrew-foo.git",\\n  "html_url": "https://github.com/new/homebrew-foo"\\n}\\n'
              ;;
            *)
              printf 'unexpected curl %s\\n' "${url}" >&2
              return 1
              ;;
          esac
        }
        lock() { :; }
        odie() { echo "Error: $*" >&2; exit 1; }
        ohai() { :; }
        onoe() { echo "Error: $*" >&2; }
        safe_cd() { cd "$1" &>/dev/null || exit 1; }
        setup_ca_certificates() { :; }
        setup_curl() { :; }
        setup_git() { :; }
        homebrew-update --auto-update --force --simulate-from-current-branch
      SH
      {
        "HOMEBREW_BREW_DEFAULT_GIT_REMOTE" => "https://github.com/Homebrew/brew",
        "HOMEBREW_BREW_GIT_REMOTE"         => "https://github.com/Homebrew/brew",
        "HOMEBREW_CACHE"                   => (test_root/"cache").to_s,
        "HOMEBREW_CASK_REPOSITORY"         => (test_root/"cask").to_s,
        "HOMEBREW_CELLAR"                  => (test_root/"cellar").to_s,
        "HOMEBREW_CORE_DEFAULT_GIT_REMOTE" => "https://github.com/Homebrew/homebrew-core",
        "HOMEBREW_CORE_GIT_REMOTE"         => "https://github.com/Homebrew/homebrew-core",
        "HOMEBREW_CORE_REPOSITORY"         => (test_root/"core").to_s,
        "HOMEBREW_DEVELOPER"               => "1",
        "HOMEBREW_LIBRARY"                 => (test_root/"Library").to_s,
        "HOMEBREW_NO_ENV_HINTS"            => "1",
        "HOMEBREW_NO_INSTALL_FROM_API"     => "1",
        "HOMEBREW_PREFIX"                  => (test_root/"prefix").to_s,
        "HOMEBREW_REPOSITORY"              => repository.to_s,
        "HOMEBREW_USER_AGENT_CURL"         => "Homebrew/test",
      },
    )

    expect(status.success?).to be true
    expect(stderr).to be_empty
    expect(args_file.read).to eq("update-report\n--force\n--simulate-from-current-branch\n")
    expect((repository/".git/REDIRECTED_REMOTES").read).to eq(
      "#{tap_path}\thttps://github.com/new/homebrew-foo.git\n",
    )
    expect(metadata_queries_file.read).to eq("https://api.github.com/repos/old/homebrew-foo\n")
  end
end
