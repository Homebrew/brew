# typed: true
# frozen_string_literal: true

require "open3"

RSpec.describe "Bash" do
  include Test::Helper::Dependencies

  matcher :have_valid_bash_syntax do
    T.bind(self, T.class_of(RSpec::Matchers::DSL::Matcher))
    match do |file|
      stdout, stderr, status = Open3.capture3("/bin/bash", "-n", file)

      @actual = [file, stderr]

      stdout.empty? && status.success?
    end

    failure_message do |(file, stderr)|
      "expected that #{file} is a valid Bash file:\n#{stderr}"
    end
  end

  describe "brew" do
    subject(:brew) { HOMEBREW_LIBRARY_PATH.parent.parent/"bin/brew" }

    it { is_expected.to have_valid_bash_syntax }

    it "rejects mismatched real and effective UIDs before dispatching a command" do
      results = [[1000, 1001], [0, 1000], [1000, 0]].map do |uid, euid|
        # Bash's UID and EUID are read-only, so substitute them in the script.
        script = brew.read.gsub("${UID}", uid.to_s).gsub("${EUID}", euid.to_s)
        stdout, stderr, status = Open3.capture3("/bin/bash", "-puc", script, brew.to_s, "--prefix")
        [stdout, stderr, status.exitstatus]
      end

      expect(results)
        .to all(eq(["", "Error: Running Homebrew with different real and effective UIDs is not supported.\n", 1]))
    end
  end

  test_each(%w[formulae casks]) do |command|
    describe "brew #{command}" do
      before do
        ENV["HOMEBREW_LIBRARY"] = HOMEBREW_LIBRARY_PATH.parent.to_s
        ENV["HOMEBREW_NO_REQUIRE_TAP_TRUST"] = nil
      end

      it "skips the Bash fast path when Ruby is required" do
        ENV["HOMEBREW_FORCE_RUBY_COMMAND"] = "1"
        stdout, stderr, status = Open3.capture3(
          "/bin/bash", "-c", <<~BASH, "bash", command
            source() {
              case "$1" in
                */cmd/formulae.sh | */cmd/casks.sh) echo 'Bash fast path'; exit 1 ;;
                */help.sh) echo 'Ruby fallback'; exit 0 ;;
                *) builtin source "$@" ;;
              esac
            }
            source "${HOMEBREW_LIBRARY}/Homebrew/brew.sh" "$1"
          BASH
        )

        expect([stdout, stderr, status.success?]).to eq(["Ruby fallback\n", "", true])
      end

      it "does not fall back to Ruby when the output pipe closes" do
        cache = mktmpdir
        ENV["HOMEBREW_NO_INSTALL_FROM_API"] = nil
        ENV["HOMEBREW_CACHE"] = cache.to_s
        (cache/"api").mkpath
        package_type = if command == "formulae"
          "formula"
        else
          "cask"
        end
        (cache/"api/#{package_type}_names.txt")
          .write((1..10_000).map { |i| format("item%05d\n", i) }.join)

        stdout, stderr, status = Open3.capture3(
          "/bin/bash", "-c", <<~BASH, "bash", command
            source "${HOMEBREW_LIBRARY}/Homebrew/cmd/$1.sh"
            homebrew-trusted-items() { return 0; }
            HOMEBREW_BREW_FILE=/usr/bin/false
            "homebrew-$1" | head -n 1
          BASH
        )

        expect([stdout, stderr, status.success?]).to eq(["item00001\n", "", true])
      end

      it "falls back to Ruby without jq quietly when completing" do
        ENV["HOMEBREW_COMPLETION"] = "1"
        stdout, stderr, status = Open3.capture3(
          "/bin/bash", "-c", <<~BASH, "bash", command
            source "${HOMEBREW_LIBRARY}/Homebrew/cmd/$1.sh"
            homebrew-trusted-items() { return 1; }
            HOMEBREW_BREW_FILE=/bin/echo
            "homebrew-$1"
          BASH
        )

        expect([stdout, stderr, status.success?]).to eq(["#{command}\n", "", true])
      end

      it "lists items without jq, Ruby or a blank line when no taps are installed" do
        cache = mktmpdir
        ENV["HOMEBREW_NO_INSTALL_FROM_API"] = nil
        ENV["HOMEBREW_CACHE"] = cache.to_s
        ENV["HOMEBREW_REPOSITORY"] = mktmpdir.to_s
        (cache/"api").mkpath
        package_type = if command == "formulae"
          "formula"
        else
          "cask"
        end
        (cache/"api/#{package_type}_names.txt").write("item1\nitem2")
        script = <<~BASH
          source "${HOMEBREW_LIBRARY}/Homebrew/cmd/$1.sh"
          type() { [[ "$*" != "-P jq" ]] && builtin type "$@"; }
          HOMEBREW_BREW_FILE=/bin/echo
          "homebrew-$1"
        BASH

        outputs = [{}, { "HOMEBREW_NO_REQUIRE_TAP_TRUST" => "1" }, { "HOMEBREW_NO_INSTALL_FROM_API" => "1" }]
                  .map { |env| Open3.capture3(env, "/bin/bash", "-c", script, "bash", command).first(2) }

        expect(outputs).to eq([["item1\nitem2\n", ""], ["item1\nitem2\n", ""], ["", ""]])
      end

      it "lists official tap items by name only" do
        ensure_test_dependency!(which("jq"), "jq is not installed.")
        repository = mktmpdir
        config_home = mktmpdir
        ENV["HOMEBREW_NO_INSTALL_FROM_API"] = "1"
        ENV["HOMEBREW_REPOSITORY"] = repository.to_s
        ENV["HOMEBREW_USER_CONFIG_HOME"] = config_home.to_s
        ENV["HOMEBREW_MACOS"] = "1" if OS.mac?
        official_tap, item_dir = if command == "formulae"
          ["homebrew-core", "Formula"]
        else
          ["homebrew-cask", "Casks/i"]
        end
        { "homebrew/#{official_tap}" => "item1", "user/homebrew-tap" => "item2" }.each do |tap, item|
          path = repository/"Library/Taps/#{tap}/#{item_dir}/#{item}.rb"
          path.dirname.mkpath
          FileUtils.touch path
        end
        (config_home/"trust.json").write('{"trustedtaps":["user/tap"]}')

        stdout, stderr, status = Open3.capture3(
          "/bin/bash", "-c", <<~BASH, "bash", command
            source "${HOMEBREW_LIBRARY}/Homebrew/cmd/$1.sh"
            HOMEBREW_BREW_FILE=/bin/echo
            "homebrew-$1"
          BASH
        )

        expect([stdout, stderr, status.success?]).to eq(["item1\nitem2\nuser/tap/item2\n", "", true])
      end
    end
  end

  describe "brew.sh" do
    it "ignores an inherited `HOMEBREW_BASH_COMMAND` for commands without a Bash implementation" do
      ENV["HOMEBREW_LIBRARY"] = HOMEBREW_LIBRARY_PATH.parent.to_s
      ENV["HOMEBREW_BASH_COMMAND"] = "/inherited/command.sh"
      stdout, stderr, status = Open3.capture3(
        "/bin/bash", "-c", <<~BASH, "bash", "services"
          source() {
            case "$1" in
              /inherited/command.sh) echo 'Inherited command'; exit 1 ;;
              */utils/analytics.sh) setup-analytics() { :; } ;;
              */utils/ruby.sh) echo 'Ruby fallback'; exit 0 ;;
              *) builtin source "$@" ;;
            esac
          }
          source "${HOMEBREW_LIBRARY}/Homebrew/brew.sh" "$1"
        BASH
      )

      expect([stdout, stderr, status.success?]).to eq(["Ruby fallback\n", "", true])
    end
  end

  describe "arithmetic on environment values" do
    let(:marker) { mktmpdir/"marker" }
    let(:payload) { "x[$(touch #{marker})0]" }

    before { ENV["HOMEBREW_LIBRARY"] = HOMEBREW_LIBRARY_PATH.parent.to_s }

    def brew_sh_value(name)
      stdout, stderr, status = Open3.capture3(
        "/bin/bash", "-c", <<~BASH, "bash", "info"
          source() {
            case "$1" in
              */utils/curl.sh) echo "${#{name}-unset}"; exit 0 ;;
              *) builtin source "$@" ;;
            esac
          }
          source "${HOMEBREW_LIBRARY}/Homebrew/brew.sh" "$1"
        BASH
      )
      [stdout, stderr, status.success?]
    end

    test_each(%w[
      HOMEBREW_API_AUTO_UPDATE_SECS
      HOMEBREW_AUTO_UPDATE_SECS
      HOMEBREW_COMMAND_DEPTH
      HOMEBREW_CURL_RETRIES
    ]) do |name|
      it "does not evaluate an inherited `#{name}`" do
        ENV[name] = payload

        expected = if name == "HOMEBREW_COMMAND_DEPTH"
          "1\n"
        else
          "unset\n"
        end
        expect([*brew_sh_value(name), marker.exist?]).to eq([expected, "", true, false])
      end
    end

    it "reads a leading zero as decimal" do
      ENV["HOMEBREW_CURL_RETRIES"] = "08"

      expect(brew_sh_value("HOMEBREW_CURL_RETRIES")).to eq(["8\n", "", true])
    end
  end

  describe "OS detection" do
    it "ignores an inherited `HOMEBREW_MACOS` or `HOMEBREW_LINUX`" do
      ENV["HOMEBREW_MACOS"] = "1"
      ENV["HOMEBREW_LINUX"] = nil
      stdout, stderr, status = Open3.capture3(
        "/bin/bash", "-c", <<~BASH, "bash", (HOMEBREW_LIBRARY_PATH/"utils/os.sh").to_s
          OSTYPE=linux-gnu
          source "$1"
          printf "%s,%s" "${HOMEBREW_MACOS-unset}" "${HOMEBREW_LINUX-unset}"
        BASH
      )

      expect([stdout, stderr, status.success?]).to eq(["unset,1", "", true])
    end
  end

  describe "URL environment variables" do
    before { ENV["HOMEBREW_LIBRARY"] = HOMEBREW_LIBRARY_PATH.parent.to_s }

    def run_brew_sh(variable, value)
      ENV[variable] = value
      Open3.capture3(
        "/bin/bash", "-c", <<~BASH, "bash", "info"
          source() {
            case "$1" in
              */utils/ruby.sh) echo 'Ruby fallback'; exit 0 ;;
              *) builtin source "$@" ;;
            esac
          }
          source "${HOMEBREW_LIBRARY}/Homebrew/brew.sh" "$1"
        BASH
      )
    end

    test_each(%w[
      HOMEBREW_API_DOMAIN
      HOMEBREW_ARTIFACT_DOMAIN
      HOMEBREW_BOTTLE_DOMAIN
      HOMEBREW_PIP_INDEX_URL
    ]) do |variable|
      it "rejects `#{variable}` values that curl would parse as options" do
        stdout, stderr, status = run_brew_sh(variable, "-K/tmp/config")

        expect(stdout).to eq("")
        expect(stderr).to include("#{variable} must not start with '-': '-K/tmp/config'.")
        expect(status.success?).to be(false)
      end

      it "accepts `#{variable}` URLs that do not start with `-`" do
        ["https://mirror.example.com/bottles", "file:///tmp/mirror", "mirror.example.com/bottles"].each do |value|
          _, stderr, = run_brew_sh(variable, value)

          expect(stderr).not_to include("must not start with")
        end
      end
    end
  end

  describe "setup-locale" do
    it "uses the macOS locale charmap rather than the locale name", :needs_macos do
      setup_locale = [
        "/bin/bash", "-c", <<~BASH, "bash", (HOMEBREW_LIBRARY_PATH/"utils/os.sh").to_s
          source "$1"
          locale() {
            [[ "${LC_CTYPE:-${LANG:-}}" == "UTF-8" ]] && printf "UTF-8" || printf "US-ASCII"
          }
          setup-locale
          printf "%s" "${LC_ALL-unset}"
        BASH
      ]
      invalid_stdout, invalid_stderr, invalid_status = Open3.capture3(
        { "LANG" => "C.utf8", "LC_CTYPE" => nil, "LC_ALL" => nil }, *setup_locale
      )
      valid_stdout, valid_stderr, valid_status = Open3.capture3(
        { "LANG" => nil, "LC_CTYPE" => "UTF-8", "LC_ALL" => nil }, *setup_locale
      )

      expect([invalid_stdout, invalid_stderr, invalid_status.success?,
              valid_stdout, valid_stderr, valid_status.success?])
        .to eq(["en_US.UTF-8", "", true, "unset", "", true])
    end

    it "restores filtered Linux locale variables and removes their copies" do
      stdout, stderr, status = Open3.capture3(
        { "LANG" => nil, "LC_CTYPE" => nil, "LC_ALL" => nil },
        "/bin/bash", "-c", <<~'BASH', "bash", (HOMEBREW_LIBRARY_PATH/"utils/os.sh").to_s
          source "$1"
          HOMEBREW_MACOS=
          HOMEBREW_LANG=C
          HOMEBREW_LC_CTYPE=C
          HOMEBREW_LC_ALL=C.UTF-8
          locale() {
            if [[ "$1" == "charmap" ]]
            then
              [[ "${LC_ALL:-}" == "C.UTF-8" ]] && printf "UTF-8" || printf "US-ASCII"
            else
              printf "locale -a called\n" >&2
              printf "C.UTF-8\n"
            fi
          }
          setup-locale
          printf "%s\n" "${LANG-unset}" "${LC_CTYPE-unset}" "${LC_ALL-unset}" \
            "${HOMEBREW_LANG-unset}" "${HOMEBREW_LC_CTYPE-unset}" "${HOMEBREW_LC_ALL-unset}"
        BASH
      )

      expect([stdout, stderr, status.success?])
        .to eq(["C\nC\nC.UTF-8\nunset\nunset\nunset\n", "", true])
    end
  end

  describe "set-homebrew-version-from-git" do
    it "writes the cache when the current user owns the Git directory" do
      Dir.mktmpdir("brew-git-cache-") do |tmpdir|
        repository = Pathname(tmpdir)
        revision = "0123456789abcdef0123456789abcdef01234567"
        (repository/".git/refs/heads").mkpath
        (repository/".git/HEAD").write "ref: refs/heads/main\n"
        (repository/".git/refs/heads/main").write "#{revision}\n"

        stdout, stderr, status = Open3.capture3(
          { "HOMEBREW_GIT" => "git", "HOMEBREW_REPOSITORY" => repository.to_s },
          "/bin/bash", "-c", <<~BASH, "bash", (HOMEBREW_LIBRARY_PATH/"utils/git.sh").to_s
            source "$1"
            git() {
              [[ "$*" == *"describe --tags"* ]] && printf "1.2.3"
            }
            HOMEBREW_VERSION=
            set-homebrew-version-from-git
            printf "%s" "${HOMEBREW_VERSION}"
          BASH
        )

        cache_file = repository/".git/describe-cache"/revision
        expect([stdout, stderr, status.success?, cache_file.read]).to eq(["1.2.3", "", true, "1.2.3\n"])
      end
    end

    it "does not mutate the cache when the current user does not own the Git directory" do
      skip "User is root so the root directory is owned by the current user." if Process.euid.zero?

      Dir.mktmpdir("brew-git-cache-") do |tmpdir|
        repository = Pathname(tmpdir)
        (repository/".git").make_symlink "/"
        operations = repository/"operations"

        stdout, stderr, status = Open3.capture3(
          { "HOMEBREW_GIT" => "git", "HOMEBREW_REPOSITORY" => repository.to_s },
          "/bin/bash", "-c", <<~'BASH', "bash", (HOMEBREW_LIBRARY_PATH/"utils/git.sh").to_s, operations.to_s
            source "$1"
            operations="$2"
            git() {
              case "$*" in
                *"rev-parse HEAD") printf "0123456789abcdef0123456789abcdef01234567" ;;
                *"describe --tags"*) printf "1.2.3" ;;
                *) return 1 ;;
              esac
            }
            rm() { printf "rm\n" >>"${operations}"; }
            mkdir() { printf "mkdir\n" >>"${operations}"; }
            HOMEBREW_VERSION=
            set-homebrew-version-from-git
            printf "%s" "${HOMEBREW_VERSION}"
          BASH
        )

        expect([stdout, stderr, status.success?, operations.exist?]).to eq(["1.2.3", "", true, false])
      end
    end
  end

  describe "every `.sh` file" do
    it "has valid Bash syntax" do
      Pathname.glob("#{HOMEBREW_LIBRARY_PATH}/**/*.sh").each do |path|
        relative_path = path.relative_path_from(HOMEBREW_LIBRARY_PATH)
        next if relative_path.to_s.start_with?("shims/", "test/", "vendor/")

        expect(path).to have_valid_bash_syntax
      end
    end
  end

  describe "Bash completion" do
    subject { HOMEBREW_LIBRARY_PATH.parent.parent/"completions/bash/brew" }

    it { is_expected.to have_valid_bash_syntax }
  end

  describe "every shim script" do
    it "has valid Bash syntax" do
      # These have no file extension, but can be identified by their shebang.
      (HOMEBREW_LIBRARY_PATH/"shims").find do |path|
        next if path.directory?
        next if path.symlink?
        next unless path.executable?
        next if path.basename.to_s == "cc" # `bash -n` tries to parse the Ruby part
        next if path.read(12) != "#!/bin/bash\n"

        expect(path).to have_valid_bash_syntax
      end
    end
  end
end
