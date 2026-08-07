# typed: false
# frozen_string_literal: true

require "open3"

RSpec.describe "Bash" do
  matcher :have_valid_bash_syntax do
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
