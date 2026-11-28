# typed: strict
# frozen_string_literal: true

require "open3"

require "cmd/--prefix"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Prefix do
  sig { params(argv: String, cache: Pathname).returns([String, T::Boolean]) }
  def formula_path_sh(*argv, cache:)
    stdout, _, status = Open3.capture3(
      {
        "HOMEBREW_CACHE"      => cache.to_s,
        "HOMEBREW_CELLAR"     => HOMEBREW_CELLAR.to_s,
        "HOMEBREW_PREFIX"     => HOMEBREW_PREFIX.to_s,
        "HOMEBREW_REPOSITORY" => HOMEBREW_REPOSITORY.to_s,
      },
      "/bin/bash", "-c", <<~SH, "bash", (HOMEBREW_LIBRARY_PATH/"formula_path.sh").to_s, *argv
        realpath() { (cd "$1" &>/dev/null && pwd -P); }
        source "$1" && shift && homebrew-formula-path "$@"
      SH
    )
    [stdout, status.success?]
  end

  it_behaves_like "parseable arguments"

  it "prints Homebrew's prefix and a Formula's prefix", :integration_test do
    expect { brew_sh "--prefix" }
      .to output("#{ENV.fetch("HOMEBREW_PREFIX")}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success

    env = {
      "HOMEBREW_BREW_SH" => test_prefix_brew_sh,
      "HOMEBREW_CACHE"   => mktmpdir.to_s,
      "HOMEBREW_TEMP"    => HOMEBREW_TEMP.to_s,
      "https_proxy"      => "http://127.0.0.1:1",
    }
    keg = HOMEBREW_CELLAR/"testball2/1.0"
    keg.mkpath
    %w[testball2 testball-alias].each do |name|
      (HOMEBREW_PREFIX/"opt"/name).make_relative_symlink(keg)
      expect { brew_sh "--prefix", name, env }
        .to output("#{HOMEBREW_PREFIX}/opt/testball2\n").to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end

    (CoreTap.instance.alias_dir/"testball-alias").make_relative_symlink(setup_test_formula("testball"))
    %w[testball testball-alias].each do |name|
      expect { brew_sh "--prefix", name, env.merge("HOMEBREW_NO_INSTALL_FROM_API" => "1") }
        .to output("#{HOMEBREW_PREFIX}/opt/testball\n").to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end
  end

  it "leaves an old name whose rack symlink points at another formula to the Ruby command" do
    keg = HOMEBREW_CELLAR/"testball/0.1"
    keg.mkpath
    # `brew migrate` leaves the old name's rack behind as a symlink.
    %w[testball-old testball-renamed].each do |name|
      (HOMEBREW_CELLAR/name).make_relative_symlink(keg.parent)
    end
    cache = mktmpdir
    (cache/"api").mkpath
    (cache/"api/formula_names.txt").write("testball\ntestball2\n")
    (cache/"api/formula_aliases.txt").write("testball-old|testball2\ntestball-renamed|testball\n")

    # Ruby resolves the old name to the installed rack, even though the API
    # now lists it as an alias of another formula.
    expect(Formulary.to_rack("testball-old")).to eq(HOMEBREW_CELLAR/"testball")
    expect(formula_path_sh("--prefix", "testball-old", cache:)).to eq(["", false])
    expect(formula_path_sh("--cellar", "testball-old", cache:)).to eq(["", false])

    # A rack symlink that agrees with the API is still answered in Bash.
    expect(formula_path_sh("--prefix", "testball-renamed", cache:))
      .to eq(["#{HOMEBREW_PREFIX}/opt/testball\n", true])
    expect(formula_path_sh("--cellar", "testball-renamed", cache:))
      .to eq(["#{HOMEBREW_CELLAR}/testball\n", true])
  end

  it "prints the prefix for a Formula" do
    cmd = described_class.new(["testball"])
    allow(cmd.args.named).to receive(:to_resolved_formulae)
      .and_return([instance_double(Formula, opt_prefix: HOMEBREW_PREFIX/"opt/testball")])

    expect { cmd.run }
      .to output("#{HOMEBREW_PREFIX}/opt/testball\n").to_stdout
      .and not_to_output.to_stderr
  end

  it "errors if the given Formula doesn't exist" do
    cmd = described_class.new(["nonexistent"])
    allow(cmd.args.named).to receive(:to_resolved_formulae)
      .and_raise(FormulaUnavailableError.new("nonexistent"))

    expect { cmd.run }.to raise_error(FormulaUnavailableError, /nonexistent/)
  end

  it "prints a warning when `--installed` is used and the given Formula is not installed" do
    cmd = described_class.new(["--installed", "testball"])
    allow(cmd.args.named).to receive(:to_resolved_formulae).and_return([
      instance_double(Formula, name: "testball", opt_prefix: HOMEBREW_PREFIX/"opt/testball", optlinked?: false),
    ])

    expect { cmd.run }
      .to raise_error(NotAKegError, /testball/)
  end
end
