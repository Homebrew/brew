# typed: true
# frozen_string_literal: true

require "open3"
require "lock_file"

require "cmd/shared_examples/args_parse"
require "cmd/update"

RSpec.describe Homebrew::Cmd::Update do
  let(:update_script) { repository_root/"Library/Homebrew/cmd/update.sh" }
  let(:test_root) do
    (repository_root/"tmp").mkpath
    Pathname(Dir.mktmpdir("brew-update-", repository_root/"tmp"))
  end
  let(:repository_root) { HOMEBREW_LIBRARY_PATH.parent.parent }

  after do
    FileUtils.rm_rf test_root
  end

  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "update", shell: true

  def run_update_shell(script, env)
    # Stop Git finding the enclosing checkout, e.g. after a failed `git init`. Use the
    # parent as Git ignores a ceiling that is the current directory (e.g. `test_root`).
    Bundler.with_unbundled_env do
      Open3.capture3(env.merge("GIT_CEILING_DIRECTORIES" => test_root.dirname.to_s), "/bin/bash", "-c", script)
    end
  end

  def setup_update_utils
    (test_root/"Library/Homebrew/utils").mkpath
    FileUtils.ln_s repository_root/"Library/Homebrew/utils.sh", test_root/"Library/Homebrew/utils.sh"
    %w[api cmd curl executables formatter lock tool tty].each do |name|
      FileUtils.ln_s repository_root/"Library/Homebrew/utils/#{name}.sh",
                     test_root/"Library/Homebrew/utils/#{name}.sh"
    end
    FileUtils.ln_s repository_root/"Library/Homebrew/utils/lock_sh", test_root/"Library/Homebrew/utils/lock_sh"
  end

  it "stops Git from finding the enclosing repository" do
    stdout, _stderr, status = run_update_shell(
      <<~SH,
        "#{Utils::Git.git}" -C "#{test_root}" rev-parse --git-dir
      SH
      {},
    )

    expect([status.success?, stdout]).to eq([false, ""])
  end

  test_each([
    ["explicit brew default", "HOMEBREW_BREW_GIT_REMOTE", "https://github.com/Homebrew/brew", "mirror/core"],
    ["explicit core default", "HOMEBREW_CORE_GIT_REMOTE", "mirror/brew", "https://github.com/Homebrew/homebrew-core"],
    ["implicit defaults", "", "mirror/brew", "mirror/core"],
    ["non-default remotes", "", "other/brew", "other/homebrew-core"],
  ].product(["", "--auto-update"])) do |(description, user_set_vars, brew_remote, core_remote), option|
    it "honours #{description} during update #{option}" do
      setup_update_utils
      FileUtils.ln_s repository_root/"Library/Homebrew/shims", test_root/"Library/Homebrew/shims"
      (test_root/"core").mkpath
      remote_base = (description == "non-default remotes") ? "other" : "https://github.com/Homebrew"

      _stdout, stderr, status = run_update_shell(
        <<~SH,
          source "#{update_script}"
          git() {
            case "$*" in
              fetch*) return 0 ;;
              "config --local --get remote.origin.url")
                "#{Utils::Git.git}" -C "#{test_root}" remote get-url origin > "#{test_root}/remotes"
                "#{Utils::Git.git}" -C "#{test_root}/core" remote get-url origin >> "#{test_root}/remotes"
                exit
                ;;
            esac
            "#{Utils::Git.git}" "$@"
          }
          for repository in "#{test_root}" "#{test_root}/core"
          do
            git -C "${repository}" init -q
          done
          git -C "#{test_root}" remote add origin mirror/brew
          git -C "#{test_root}/core" remote add origin mirror/core
          lock() { :; }
          homebrew-update #{option}
        SH
        {
          "HOMEBREW_BREW_DEFAULT_GIT_REMOTE"      => "https://github.com/Homebrew/brew",
          "HOMEBREW_BREW_GIT_REMOTE"              => "#{remote_base}/brew",
          "HOMEBREW_CORE_DEFAULT_GIT_REMOTE"      => "https://github.com/Homebrew/homebrew-core",
          "HOMEBREW_CORE_GIT_REMOTE"              => "#{remote_base}/homebrew-core",
          "HOMEBREW_CORE_REPOSITORY"              => (test_root/"core").to_s,
          "HOMEBREW_FORCE_BREWED_CA_CERTIFICATES" => nil,
          "HOMEBREW_FORCE_BREWED_CURL"            => nil,
          "HOMEBREW_FORCE_BREWED_GIT"             => nil,
          "HOMEBREW_LIBRARY"                      => (test_root/"Library").to_s,
          "HOMEBREW_NO_INSTALL_FROM_API"          => "1",
          "HOMEBREW_REPOSITORY"                   => test_root.to_s,
          "HOMEBREW_USER_SET_VARS"                => user_set_vars,
        },
      )

      expect([status.success?, (test_root/"remotes").read]).to eq([true, "#{brew_remote}\n#{core_remote}\n"]),
                                                               stderr
    end
  end

  it "installs Git when the Git wrapper cannot find an executable" do
    setup_update_utils
    (test_root/"Library/Homebrew/shims/shared").mkpath
    (test_root/"Library/Homebrew/shims/shared/git").write "#!/bin/bash\nexit 1\n"
    (test_root/"Library/Homebrew/shims/shared/git").chmod(0755)

    stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        brew() { echo "$*"; }
        setup_git() { echo git-ready; exit 0; }
        homebrew-update
      SH
      {
        "GIT_EXECUTABLE"                        => nil,
        "HOMEBREW_CELLAR"                       => (test_root/"Cellar").to_s,
        "HOMEBREW_FORCE_BREWED_CA_CERTIFICATES" => nil,
        "HOMEBREW_FORCE_BREWED_CURL"            => nil,
        "HOMEBREW_LIBRARY"                      => (test_root/"Library").to_s,
        "HOMEBREW_NO_INSTALL_FROM_API"          => nil,
        "HOMEBREW_REPOSITORY"                   => test_root.to_s,
      },
    )

    expect([status.exitstatus, stdout, stderr]).to eq([0, "install git\ngit-ready\n", ""])
  end

  test_each(%w[git curl]) do |tool|
    it "keeps #{tool} selection after an ordinary command failure" do
      setup_update_utils
      executable = test_root/tool
      executable.write "#!/bin/bash\necho original-error >&2\nexit 128\n"
      executable.chmod(0755)
      selection_cache = test_root/"cache/tool-selection"/tool
      selection_cache.dirname.mkpath
      selection_cache.write "cached selection"

      _stdout, stderr, status = run_update_shell(
        <<~SH,
          source "#{update_script}"
          #{tool}
        SH
        {
          "#{tool.upcase}_EXECUTABLE" => executable.to_s,
          "HOMEBREW_LIBRARY"          => (test_root/"Library").to_s,
          "HOMEBREW_CACHE"            => (test_root/"cache").to_s,
        },
      )

      expect([status.exitstatus, stderr, selection_cache.exist?]).to eq([128, "original-error\n", true])
    end

    it "installs forced #{tool} when its installed executable was rejected" do
      setup_update_utils
      installed_tool = test_root/"opt"/tool/"bin"/tool
      installed_tool.dirname.mkpath
      installed_tool.write "#!/bin/bash\nexit 1\n"
      installed_tool.chmod(0755)

      stdout, stderr, status = run_update_shell(
        <<~SH,
          source "#{update_script}"
          git() { return 0; }
          brew() { echo "$*"; }
          setup_#{tool}() { echo ready; exit 0; }
          git_init_if_necessary() { exit 2; }
          homebrew-update
        SH
        {
          "HOMEBREW_CELLAR"                       => (test_root/"Cellar").to_s,
          "HOMEBREW_PREFIX"                       => test_root.to_s,
          "HOMEBREW_FORCE_BREWED_CA_CERTIFICATES" => nil,
          "HOMEBREW_FORCE_BREWED_CURL"            => (tool == "curl") ? "1" : nil,
          "HOMEBREW_FORCE_BREWED_GIT"             => (tool == "git") ? "1" : nil,
          "HOMEBREW_LIBRARY"                      => (test_root/"Library").to_s,
          "HOMEBREW_NO_INSTALL_FROM_API"          => nil,
          "HOMEBREW_REPOSITORY"                   => test_root.to_s,
          "HOMEBREW_#{tool.upcase}"               => "/usr/bin/#{tool}",
        },
      )

      expect([status.exitstatus, stdout, stderr]).to eq([0, "install #{tool}\nready\n", ""])
    end
  end

  it "detects shallow clones and their linked worktrees but not full clones" do
    setup_update_utils
    FileUtils.ln_s repository_root/"Library/Homebrew/shims", test_root/"Library/Homebrew/shims"
    repositories = test_root/"repositories"

    stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        git() {
          "#{Utils::Git.git}" -c init.defaultBranch=main -c user.name=Homebrew \\
            -c user.email=homebrew@example.com "$@"
        }
        set -e
        mkdir -p "#{repositories}"
        cd "#{repositories}"
        git init -q remote
        git -C remote commit -q --allow-empty -m init
        git clone -q remote full
        git clone -q --depth 1 "file://#{repositories}/remote" shallow
        git -C shallow worktree add -q --detach "#{repositories}/shallow-worktree"
        for repository in full shallow shallow-worktree missing
        do
          if shallow_repository "#{repositories}/${repository}"
          then
            echo "${repository}: shallow"
          else
            echo "${repository}: full"
          fi
        done
      SH
      { "HOMEBREW_LIBRARY" => (test_root/"Library").to_s },
    )

    expect([status.success?, stdout]).to eq(
      [true, "full: full\nshallow: shallow\nshallow-worktree: shallow\nmissing: full\n"],
    ), stderr
  end

  it "uses the configured curl options for API downloads" do
    setup_update_utils

    stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        git() { return 0; }
        shallow_repository() { return 1; }
        lock() { :; }
        curl() { printf '%s\\0' "$@"; }
        git_init_if_necessary() {
          api_curl_download https://formulae.example/api/formula.jws.json /dev/null
          exit
        }
        homebrew-update
      SH
      {
        "HOMEBREW_CELLAR"                       => (test_root/"Cellar").to_s,
        "HOMEBREW_CURLRC"                       => "/path with spaces/\n--insecure",
        "HOMEBREW_CURL_RETRIES"                 => "10",
        "HOMEBREW_CURL_VERBOSE"                 => "1",
        "HOMEBREW_FORCE_BREWED_CA_CERTIFICATES" => nil,
        "HOMEBREW_FORCE_BREWED_CURL"            => nil,
        "HOMEBREW_FORCE_BREWED_GIT"             => nil,
        "HOMEBREW_LIBRARY"                      => (test_root/"Library").to_s,
        "HOMEBREW_NO_INSECURE_REDIRECT"         => "1",
        "HOMEBREW_REPOSITORY"                   => test_root.to_s,
      },
    )

    expect([status.success?, stderr, stdout.split("\0").first(8)])
      .to eq([true, "", ["-q", "--config", "/path with spaces/\n--insecure", "--retry", "10", "--verbose",
                         "--proto-redir", "=https"]])
  end

  it "retries a failed conditional API download without the time condition" do
    cache_path = test_root/"cache/api/formula.jws.json"
    requests_file = test_root/"requests.txt"
    update_failed_file = test_root/"update_failed.txt"
    setup_update_utils
    cache_path.dirname.mkpath
    cache_path.write "cached"

    _stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        curl() {
          if [[ "$*" == *"--time-cond"* ]]
          then
            echo conditional >> "#{requests_file}"
            return 56
          fi

          echo unconditional >> "#{requests_file}"
          printf fresh > "#{cache_path}"
        }
        fetch_api_file formula.jws.json "#{update_failed_file}"
      SH
      {
        "HOMEBREW_API_DEFAULT_DOMAIN"  => "https://formulae.example/api",
        "HOMEBREW_API_DOMAIN"          => nil,
        "HOMEBREW_CACHE"               => (test_root/"cache").to_s,
        "HOMEBREW_CURL_SPEED_LIMIT"    => "100",
        "HOMEBREW_CURL_SPEED_TIME"     => "5",
        "HOMEBREW_CURL_SUPPORTS_ETAGS" => nil,
        "HOMEBREW_LIBRARY"             => (test_root/"Library").to_s,
        "HOMEBREW_PREFIX"              => HOMEBREW_PREFIX.to_s,
        "HOMEBREW_USER_AGENT_CURL"     => "Homebrew/test",
      },
    )

    expect([status.success?, stderr, requests_file.read, cache_path.read, update_failed_file.exist?]).to eq(
      [true, "", "conditional\nunconditional\n", "fresh", false],
    )
  end

  describe "API ETag revalidation" do
    let(:cache_dir) { test_root/"cache directory/\n--insecure" }
    let(:cache_path) { cache_dir/"api/formula.jws.json" }
    let(:etag_path) { Pathname("#{cache_path}.etag") }
    let(:new_etag_path) { Pathname("#{cache_path}.etag.new") }
    let(:args_file) { test_root/"curl-args.txt" }
    let(:update_failed_file) { test_root/"update_failed.txt" }

    def fetch_with_curl_response(status_code:, body: "", etag: "", saved_etag: '"old"', curl_supports_etags: "1",
                                 api_domain: nil, saved_url: nil, exit_code: 0)
      setup_update_utils
      cache_path.dirname.mkpath
      cache_path.write "cached"
      args_file.write ""
      etag_path.write saved_etag if saved_etag
      Pathname("#{etag_path}.url").write saved_url || "#{api_domain || "https://formulae.example/api"}/formula.jws.json"

      _stdout, stderr, status = run_update_shell(
        <<~SH,
          source "#{update_script}"
          curl() {
            printf '%s\\0' "$@" >> "#{args_file}"
            [[ "${!#}" == "#{api_domain}/"* ]] && return 22
            local output etag_save
            while [[ $# -gt 0 ]]
            do
              case "$1" in
                --output) output="$2"; shift ;;
                --etag-save) etag_save="$2"; shift ;;
              esac
              shift
            done
            [[ -n "${etag_save}" ]] && printf '%s' '#{etag}' > "${etag_save}"
            [[ -n '#{body}' ]] && printf '%s' '#{body}' > "${output}"
            printf '%s' '#{status_code}'
            return #{exit_code}
          }
          fetch_api_file formula.jws.json "#{update_failed_file}"
        SH
        {
          "HOMEBREW_API_DEFAULT_DOMAIN"  => "https://formulae.example/api",
          "HOMEBREW_API_DOMAIN"          => api_domain,
          "HOMEBREW_CACHE"               => cache_dir.to_s,
          "HOMEBREW_CURL_SPEED_LIMIT"    => "100",
          "HOMEBREW_CURL_SPEED_TIME"     => "5",
          "HOMEBREW_CURL_SUPPORTS_ETAGS" => curl_supports_etags,
          "HOMEBREW_LIBRARY"             => (test_root/"Library").to_s,
          "HOMEBREW_PREFIX"              => HOMEBREW_PREFIX.to_s,
          "HOMEBREW_USER_AGENT_CURL"     => "Homebrew/test",
        },
      )

      conditional_flags = %w[--etag-compare --etag-save --time-cond]
      {
        success:   status.success? && stderr.empty? && !update_failed_file.exist?,
        curl_args: args_file.read.split("\0").each_cons(2).filter_map do |flag, value|
          [flag, value] if conditional_flags.include?(flag)
        end,
        body:      cache_path.read,
        etag:      (etag_path.read if etag_path.exist?),
        temp_etag: new_etag_path.exist?,
      }
    end

    it "revalidates with the saved ETag and saves the new one with the new body" do
      expect(fetch_with_curl_response(status_code: 200, body: "fresh", etag: '"new"')).to eq(
        success:   true,
        curl_args: [
          ["--etag-save", new_etag_path.to_s],
          ["--etag-compare", etag_path.to_s],
        ],
        body:      "fresh",
        etag:      '"new"',
        temp_etag: false,
      )
    end

    it "keeps the saved ETag when the server answers 304" do
      expect(fetch_with_curl_response(status_code: 304).except(:curl_args)).to eq(
        success: true, body: "cached", etag: '"old"', temp_etag: false,
      )
    end

    it "removes the saved ETag after a 200 that carries none" do
      expect(fetch_with_curl_response(status_code: 200, body: "fresh").except(:curl_args)).to eq(
        success: true, body: "fresh", etag: nil, temp_etag: false,
      )
    end

    it "downloads a fresh body without a saved ETag" do
      expect(fetch_with_curl_response(status_code: 200, body: "fresh", etag: '"new"', saved_etag: nil)).to eq(
        success:   true,
        curl_args: [["--etag-save", new_etag_path.to_s]],
        body:      "fresh",
        etag:      '"new"',
        temp_etag: false,
      )
    end

    it "uses only the time condition when curl is older than 7.68.0" do
      expect(fetch_with_curl_response(status_code: 200, body: "fresh", curl_supports_etags: nil)).to eq(
        success:   true,
        curl_args: [["--time-cond", cache_path.to_s]],
        body:      "fresh",
        etag:      nil,
        temp_etag: false,
      )
    end

    it "downloads unconditionally from the fallback API domain" do
      result = fetch_with_curl_response(status_code: 200, body: "fresh", etag: '"new"',
                                        api_domain: "https://mirror.example/api")
      expect(result).to eq(
        success:   true,
        curl_args: [
          ["--etag-save", new_etag_path.to_s],
          ["--etag-compare", etag_path.to_s],
        ],
        body:      "fresh",
        etag:      nil,
        temp_etag: false,
      )
    end

    it "preserves the cached body and ETag after a partial download" do
      expect(fetch_with_curl_response(status_code: 200, body: "partial", etag: '"partial"', exit_code: 18)
        .except(:curl_args)).to eq(success: false, body: "cached", etag: '"old"', temp_etag: false)
    end

    it "ignores an ETag saved for a different API domain" do
      expect(fetch_with_curl_response(status_code: 200, body: "fresh", etag: '"new"',
                                      saved_url: "https://mirror.example/api/formula.jws.json")[:curl_args])
        .to eq [["--etag-save", new_etag_path.to_s]]
      expect(Pathname("#{etag_path}.url").read).to eq "https://formulae.example/api/formula.jws.json"
    end

    it "keeps the saved ETag after a 304 with curl older than 7.68.0" do
      expect(fetch_with_curl_response(status_code: 304, curl_supports_etags: nil).except(:curl_args)).to eq(
        success: true, body: "cached", etag: '"old"', temp_etag: false,
      )
    end

    it "does not overwrite a cache being refreshed by Ruby" do
      DownloadLock.new(cache_path).with_lock do
        expect(fetch_with_curl_response(status_code: 200, body: "fresh", etag: '"new"').except(:curl_args)).to eq(
          success: false, body: "cached", etag: '"old"', temp_etag: false,
        )
      end
    end
  end

  it "redetects curl ETag support when the flag is inherited" do
    setup_update_utils

    stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{test_root}/Library/Homebrew/utils.sh"
        source "#{test_root}/Library/Homebrew/utils/curl.sh"
        HOMEBREW_CURL=curl
        for version in 7.41.0 7.67.0 7.68.0 8.7.1
        do
          curl() { echo "curl ${version} (x86_64-apple-darwin) libcurl/${version}"; }
          setup-user-agents
          [[ -n "${HOMEBREW_CURL_SUPPORTS_ETAGS}" ]] && echo "${version}: yes" || echo "${version}: no"
        done
      SH
      {
        "HOMEBREW_CURL_SUPPORTS_ETAGS" => "1",
        "HOMEBREW_CURL_VERSION"        => nil,
        "HOMEBREW_LIBRARY"             => (test_root/"Library").to_s,
      },
    )

    expect([status.success?, stderr, stdout]).to eq(
      [true, "", "7.41.0: no\n7.67.0: no\n7.68.0: yes\n8.7.1: yes\n"],
    )
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

  it "disables `--merge` in the shell implementation" do
    setup_update_utils

    _stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        odie() { echo "Error: $*" >&2; exit 1; }
        homebrew-update --merge
      SH
      { "HOMEBREW_LIBRARY" => (test_root/"Library").to_s },
    )

    expect([status.success?, stderr]).to eq(
      [false, "Error: Calling the `--merge` switch is disabled! There is no replacement.\n"],
    )
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
        "HOMEBREW_BREW_GIT_REMOTE"     => "https://github.com/Homebrew/brew",
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

  it "keeps the current API file's saved ETag when removing other OS versions' API files" do
    api_internal = test_root/"cache/api/internal"
    setup_update_utils
    api_internal.mkpath
    (test_root/"repository").mkpath
    %w[
      packages.arm64_tahoe.jws.json
      packages.arm64_tahoe.jws.json.etag
      packages.arm64_tahoe.jws.json.etag.url
      packages.arm64_sequoia.jws.json
      packages.arm64_sequoia.jws.json.etag
      packages.arm64_sequoia.jws.json.etag.url
    ].each { |name| (api_internal/name).write "x" }

    _stdout, stderr, status = run_update_shell(
      <<~SH,
        source "#{update_script}"
        bottle_tag() { echo arm64_tahoe; }
        brew() { :; }
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
        "HOMEBREW_BREW_GIT_REMOTE"     => "https://github.com/Homebrew/brew",
        "HOMEBREW_CACHE"               => (test_root/"cache").to_s,
        "HOMEBREW_CELLAR"              => (test_root/"cellar").to_s,
        "HOMEBREW_LIBRARY"             => (test_root/"Library").to_s,
        "HOMEBREW_NO_INSTALL_FROM_API" => nil,
        "HOMEBREW_PREFIX"              => (test_root/"prefix").to_s,
        "HOMEBREW_REPOSITORY"          => (test_root/"repository").to_s,
      },
    )

    expect([status.success?, stderr]).to eq([true, ""])
    expect(api_internal.children.map { |path| path.basename.to_s }.sort).to eq(
      %w[packages.arm64_tahoe.jws.json packages.arm64_tahoe.jws.json.etag packages.arm64_tahoe.jws.json.etag.url],
    )
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
        "HOMEBREW_DEV_CMD_RUN"             => nil,
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
    update_env_file = test_root/"update-env.txt"
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
        brew() {
          printf '%s\\n' "$@" > "#{args_file}"
          env | grep '^HOMEBREW_UPDATE_' > "#{update_env_file}"
        }
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
        "HOMEBREW_DEV_CMD_RUN"             => nil,
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
    expect(update_env_file.read).to include(
      "HOMEBREW_UPDATE_BEFORE_OLD_HOMEBREW_FOO=abc\n",
      "HOMEBREW_UPDATE_AFTER_OLD_HOMEBREW_FOO=abc\n",
      "HOMEBREW_UPDATE_BRANCH_OLD_HOMEBREW_FOO=main\n",
    )
    expect(fetches_file.read).to eq("#{tap_path}\n")
    expect((repository/".git/REDIRECTED_REMOTES").read).to eq(
      "#{tap_path}\thttps://github.com/new/homebrew-foo.git\n",
    )
    expect(metadata_queries_file.read).to eq("https://api.github.com/repos/old/homebrew-foo\n")
  end

  it "queries redirected remote metadata only for taps" do
    args_file = test_root/"brew-args.txt"
    curl_input_file = test_root/"curl-input.txt"
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
          printf '%s\\n' "$@" >> "#{test_root}/curl-args.txt"
          cat >> "#{curl_input_file}"
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
        "HOMEBREW_CURL_VERSION"            => "7.55.0",
        "HOMEBREW_DEVELOPER"               => "1",
        "HOMEBREW_GITHUB_API_TOKEN"        => "test-token",
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
    expect((test_root/"curl-args.txt").read).not_to include("test-token")
    expect(curl_input_file.read).to eq("Authorization: token test-token\n" * 2)
  end
end
