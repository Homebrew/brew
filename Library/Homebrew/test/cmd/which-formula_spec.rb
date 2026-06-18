# typed: true
# frozen_string_literal: true

require "open3"

require "cmd/shared_examples/args_parse"
require "cmd/which-formula"

RSpec.describe Homebrew::Cmd::WhichFormula do
  it_behaves_like "parseable arguments"

  describe "which_formula" do
    let(:shell_cellar) do
      if (HOMEBREW_LIBRARY_PATH.parent.parent/"Cellar").directory?
        HOMEBREW_LIBRARY_PATH.parent.parent/"Cellar"
      else
        HOMEBREW_CELLAR
      end
    end

    before do
      # Override DATABASE_FILE to use test environment's HOMEBREW_CACHE
      test_db_file = HOMEBREW_CACHE/"api"/Homebrew::Cmd::WhichFormula::ENDPOINT
      stub_const("#{described_class}::DATABASE_FILE", test_db_file)

      db = Homebrew::Cmd::WhichFormula::DATABASE_FILE
      db.dirname.mkpath
      db.write(<<~EOS)
        foo(1.0.0):foo2 foo3
        bar(1.2.3):
        baz(10.4):baz
        qux(4.5.6):QUX
        quux:quux
      EOS

      (shell_cellar/"foo/1.0.0").mkpath
    end

    after do
      FileUtils.rm_rf shell_cellar/"foo"
    end

    it "finds formulae using the Bash command path" do
      env = {
        "HOMEBREW_BREW_FILE" => HOMEBREW_BREW_FILE.to_s,
        "HOMEBREW_CACHE"     => HOMEBREW_CACHE.to_s,
        "HOMEBREW_CELLAR"    => shell_cellar.to_s,
        "HOMEBREW_LIBRARY"   => HOMEBREW_LIBRARY_PATH.parent.to_s,
      }
      env["HOMEBREW_MACOS"] = "1" if OS.mac?
      stdout, stderr, status = Open3.capture3(
        env,
        "/bin/bash", "-c", <<~SH,
          source "$1"

          stdout_file="$(mktemp)"
          stderr_file="$(mktemp)"
          trap 'rm -f "${stdout_file}" "${stderr_file}"' EXIT

          check() {
            local label="$1"
            local expected_status="$2"
            local expected_stdout="$3"
            local expected_stderr="$4"
            shift 4

            ( "$@" ) >"${stdout_file}" 2>"${stderr_file}"
            status="$?"
            if [[ "${status}" -ne "${expected_status}" ]]
            then
              echo "${label}: expected status ${expected_status}, got ${status}" >&2
              return 1
            fi
            if ! diff -u <(printf '%s' "${expected_stdout}") "${stdout_file}" >&2
            then
              echo "${label}: stdout mismatch" >&2
              return 1
            fi
            if ! diff -u <(printf '%s' "${expected_stderr}") "${stderr_file}" >&2
            then
              echo "${label}: stderr mismatch" >&2
              return 1
            fi
          }

          check "installed and uninstalled executables" 0 $'foo\\nbaz\\nqux\\nquux\\n' "" \\
            homebrew-which-formula foo2 baz QUX quux
          HOMEBREW_NO_EMOJI=1 check "non-emoji output" 0 $'foo\\n' "" homebrew-which-formula foo2
          check "missing executable" 1 "" "" homebrew-which-formula bar

          long_verbose_option() {
            unset HOMEBREW_VERBOSE
            homebrew-which-formula --verbose bar
            local status="$?"
            [[ -n "${HOMEBREW_VERBOSE}" ]] || {
              echo "long verbose option: HOMEBREW_VERBOSE was not set" >&2
              return 2
            }
            return "${status}"
          }
          check "long verbose option" 1 "" "" long_verbose_option

          short_verbose_option() {
            unset HOMEBREW_VERBOSE
            homebrew-which-formula -v bar
            local status="$?"
            [[ -n "${HOMEBREW_VERBOSE}" ]] || {
              echo "short verbose option: HOMEBREW_VERBOSE was not set" >&2
              return 2
            }
            return "${status}"
          }
          check "short verbose option" 1 "" "" short_verbose_option

          rm -f "$(executables_txt_cache_file)"
          HOMEBREW_NO_INSTALL_FROM_API=1 check "disabled API without database" 1 "" \\
            $'Error: HOMEBREW_NO_INSTALL_FROM_API must be unset to use `brew which-formula` or `brew exec`.\\n' \\
            homebrew-which-formula foo2
        SH
        "bash", (HOMEBREW_LIBRARY_PATH/"cmd/which-formula.sh").to_s
      )

      expect(status).to be_success
      expect(stdout).to be_empty
      expect(stderr).to be_empty
    end
  end
end
