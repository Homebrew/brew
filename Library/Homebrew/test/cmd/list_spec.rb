# typed: true
# frozen_string_literal: true

require "open3"

require "cmd/list"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::List do
  let(:formulae) { %w[bar foo qux] }

  def list_versions_json(formulae: [], casks: [])
    formulae = formulae.map do |f|
      f.merge(
        linked_version:    f.fetch(:linked_version, nil),
        optlinked_version: f.fetch(:optlinked_version, nil),
        pinned_version:    f.fetch(:pinned_version, nil),
      )
    end
    casks = casks.map do |c|
      c.merge(
        pinned_version: c.fetch(:pinned_version, nil),
      )
    end
    "#{JSON.generate({ formulae:, casks: })}\n"
  end

  def install_formula_version(name, version)
    (HOMEBREW_CELLAR/name/version/"somedir").mkpath
  end

  def install_cask(token)
    Cask::CaskLoader.load(token).tap { |cask| InstallHelper.stub_cask_installation(cask) }
  end

  def run_list_bash(env = {})
    stdout, stderr, status = Open3.capture3(
      {
        "HOMEBREW_CASKROOM" => Cask::Caskroom.path.to_s,
        "HOMEBREW_CELLAR"   => HOMEBREW_CELLAR.to_s,
        "HOMEBREW_LIBRARY"  => HOMEBREW_LIBRARY_PATH.to_s,
        "HOMEBREW_PREFIX"   => HOMEBREW_PREFIX.to_s,
      }.merge(env),
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

        empty_versions_json() {
          HOMEBREW_CELLAR="${EMPTY_CELLAR}" HOMEBREW_CASKROOM="${EMPTY_CASKROOM}" \\
            homebrew-list list --versions --json
        }

        missing_jq_versions_json() {
          PATH="${NO_JQ_PATH}" HOMEBREW_PATH="${NO_JQ_PATH}" HOMEBREW_PREFIX="${NO_JQ_PREFIX}" \\
            HOMEBREW_CELLAR="${NO_JQ_CELLAR}" HOMEBREW_CASKROOM="${NO_JQ_CASKROOM}" \\
            homebrew-list list --versions --json
        }

        check "formulae and casks" 0 "${EXPECTED_PLAIN}" "" homebrew-list list
        check "formula and cask versions JSON" 0 "${EXPECTED_JSON}" "" homebrew-list list --versions --json
        check "formula versions JSON" 0 "${EXPECTED_FORMULA_JSON}" "" \\
          homebrew-list list --versions --json --formula
        check "cask versions JSON" 0 "${EXPECTED_CASK_JSON}" "" homebrew-list list --versions --json --cask
        check "empty versions JSON" 0 "${EXPECTED_EMPTY_JSON}" "" empty_versions_json
        check "JSON without versions" 1 "" \\
          $'Error: `brew list --json` requires `--versions`.\\n' \\
          homebrew-list list --json
        check "JSON with ls flags" 1 "" \\
          $'Error: `brew list --versions --json` cannot be combined with `-1`, `-l`, `-r` or `-t`.\\n' \\
          homebrew-list list --versions --json -1
        check "JSON with formula and cask filters" 1 "" \\
          $'Error: `--formula` and `--cask` are mutually exclusive.\\n' \\
          homebrew-list list --versions --json --formula --cask
        check "missing jq" 1 "" $'Error: jq is required for brew list --versions --json.\\n' \\
          missing_jq_versions_json
      SH
      "bash", (HOMEBREW_LIBRARY_PATH/"list.sh").to_s
    )
    $stdout.print stdout
    $stderr.print stderr
    status
  end

  it_behaves_like "parseable arguments"

  it "prints all installed formulae" do
    formulae.each do |f|
      install_formula_version f, "1.0"
    end

    expect { described_class.new(["--formula"]).run }
      .to output("#{formulae.join("\n")}\n").to_stdout
      .and not_to_output.to_stderr
  end

  describe "filtering by install-on-request status" do
    let(:on_request) do
      formula("on-request") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/on-request-1.0"
      end
    end
    let(:dependency) do
      formula("dependency") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependency-1.0"
      end
    end

    before do
      allow(Formula).to receive(:installed).and_return([on_request, dependency])
      allow(Tab).to receive(:for_formula).with(on_request)
                                         .and_return(instance_double(Tab, installed_on_request: true))
      allow(Tab).to receive(:for_formula).with(dependency)
                                         .and_return(instance_double(Tab, installed_on_request: false))
    end

    it "lists only formulae installed on request with --installed-on-request" do
      expect { described_class.new(["--installed-on-request"]).run }.to output("on-request\n").to_stdout
    end

    it "lists only dependencies with --no-installed-on-request" do
      expect { described_class.new(["--no-installed-on-request"]).run }.to output("dependency\n").to_stdout
    end

    it "lists every formula by category when both flags are combined" do
      expect { described_class.new(["--installed-on-request", "--no-installed-on-request"]).run }
        .to output("dependency: installed as dependency\non-request: installed on request\n").to_stdout
    end
  end

  it "covers Bash list output and errors", :cask, :needs_jq do
    install_formula_version "testball", "0.1"
    install_formula_version "testball", "0.2"
    (HOMEBREW_PREFIX/"var/homebrew/linked").mkpath
    FileUtils.ln_s HOMEBREW_CELLAR/"testball/0.1", HOMEBREW_PREFIX/"var/homebrew/linked/testball"
    (HOMEBREW_PREFIX/"opt").mkpath
    FileUtils.ln_s HOMEBREW_CELLAR/"testball/0.2", HOMEBREW_PREFIX/"opt/testball"
    (HOMEBREW_PREFIX/"var/homebrew/pinned").mkpath
    FileUtils.ln_s HOMEBREW_CELLAR/"testball/0.2", HOMEBREW_PREFIX/"var/homebrew/pinned/testball"

    install_cask "local-caffeine"
    (HOMEBREW_PREFIX/"var/homebrew/pinned_casks").mkpath
    FileUtils.ln_s Cask::Caskroom.path/"local-caffeine/1.2.3",
                   HOMEBREW_PREFIX/"var/homebrew/pinned_casks/local-caffeine"

    empty_cellar = mktmpdir
    empty_caskroom = mktmpdir
    no_jq_root = mktmpdir
    no_jq_cellar = no_jq_root/"Cellar"
    no_jq_caskroom = no_jq_root/"Caskroom"
    no_jq_prefix = no_jq_root/"prefix"
    no_jq_cellar.mkpath
    no_jq_caskroom.mkpath
    no_jq_prefix.mkpath
    formulae_json = [{ name: "testball", versions: ["0.1", "0.2"], linked_version: "0.1",
                       optlinked_version: "0.2", pinned_version: "0.2" }]
    casks_json = [{ token: "local-caffeine", versions: ["1.2.3"], pinned_version: "1.2.3" }]

    expect do
      expect(run_list_bash(
               "EMPTY_CASKROOM"        => empty_caskroom.to_s,
               "EMPTY_CELLAR"          => empty_cellar.to_s,
               "EXPECTED_CASK_JSON"    => list_versions_json(casks: casks_json),
               "EXPECTED_EMPTY_JSON"   => list_versions_json,
               "EXPECTED_FORMULA_JSON" => list_versions_json(formulae: formulae_json),
               "EXPECTED_JSON"         => list_versions_json(formulae: formulae_json, casks: casks_json),
               "EXPECTED_PLAIN"        => "testball\nlocal-caffeine\n",
               "NO_JQ_CASKROOM"        => no_jq_caskroom.to_s,
               "NO_JQ_CELLAR"          => no_jq_cellar.to_s,
               "NO_JQ_PATH"            => no_jq_root.to_s,
               "NO_JQ_PREFIX"          => no_jq_prefix.to_s,
             )).to be_success
    end
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
  end

  it "fails when versions JSON reaches the Ruby fallback" do
    expect { described_class.new(["--versions", "--json"]).run }
      .to raise_error(UsageError, /`brew list --versions --json` is only supported by the fast Bash path with `jq`\./)
  end

  it "fails clearly when JSON without versions reaches the Ruby fallback" do
    expect { described_class.new(["--json"]).run }
      .to raise_error(UsageError, /`brew list --json` requires `--versions`\./)
  end

  it "prints pinned formulae and casks", :cask, :integration_test do
    setup_test_formula "testball", tab_attributes: { installed_on_request: true }
    Formula["testball"].pin
    cask = Cask::CaskLoader.load("local-caffeine")
    InstallHelper.stub_cask_installation(cask)
    cask.pin

    expect { brew "list", "--pinned", "--versions" }
      .to output("local-caffeine 1.2.3\ntestball 0.1\n").to_stdout
      .and be_a_success

    cask.unpin
  end

  it "fails only for explicitly named missing pinned packages", :cask do
    install_formula_version "testball", "0.1"
    (HOMEBREW_PREFIX/"var/homebrew/pinned").mkpath
    FileUtils.ln_s HOMEBREW_CELLAR/"testball/0.1", HOMEBREW_PREFIX/"var/homebrew/pinned/testball"
    cask = Cask::CaskLoader.load("local-caffeine")
    InstallHelper.stub_cask_installation(cask)
    cask.pin

    expect { described_class.new(["--pinned", "--versions", "testball", "local-caffeine", "missing"]).run }
      .to output("local-caffeine 1.2.3\ntestball 0.1\n").to_stdout
    expect(Homebrew).to have_failed

    cask.unpin
  end

  it "warns for explicitly named unpinned packages", :cask do
    cask = Cask::CaskLoader.load("local-caffeine")
    InstallHelper.stub_cask_installation(cask)

    expect { described_class.new(["--pinned", "--cask", "local-caffeine"]).run }
      .to not_to_output.to_stdout
      .and output(/local-caffeine not pinned/).to_stderr
  end

  it "does not fail for unpinned Caskroom entries without named arguments", :cask do
    (Cask::Caskroom.path/"broken").mkpath

    expect { described_class.new(["--pinned", "--cask"]).run }
      .to not_to_output.to_stdout
  end
end
