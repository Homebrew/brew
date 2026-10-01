# typed: strict
# frozen_string_literal: true

require "cmd/missing"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Missing do
  it_behaves_like "parseable arguments"

  it "prints missing Formula and Cask dependencies", :cask, :integration_test, :no_api do
    setup_test_formula "foo"
    setup_test_formula "bar"

    (HOMEBREW_CELLAR/"bar/1.0").mkpath
    (HOMEBREW_CELLAR/"bar/1.0/INSTALL_RECEIPT.json").write(
      JSON.generate({
        "homebrew_version"     => "1.1.6",
        "runtime_dependencies" => [{ "full_name" => "foo", "version" => "1.0" }],
      }),
    )

    expect { brew "missing" }
      .to output("foo\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_failure

    setup_test_formula "unar"
    cask = Cask::CaskLoader.load("with-depends-on-everything")
    InstallHelper.stub_cask_installation(cask)
    expect { brew "missing", cask.token }
      .to output(/local-caffeine.*unar/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_failure
  end

  it "prints missing cask dependencies", :cask, :no_api do
    cask = instance_double(Cask::Cask, full_name: "with-depends-on-everything",
                                       to_s:      "with-depends-on-everything")
    tab = instance_double(Cask::Tab, runtime_dependencies: {
      "cask"    => [{ "full_name" => "local-caffeine" }],
      "formula" => [{ "full_name" => "unar" }],
    })
    HOMEBREW_CELLAR.mkpath
    allow(Formula).to receive(:installed).and_return([])
    allow(Cask::Caskroom).to receive(:casks).and_return([cask])
    allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(tab)

    expect { described_class.new([]).run }
      .to output("local-caffeine unar\n").to_stdout

    expect(Homebrew).to have_failed
  end

  it "prints missing cask dependencies for named casks", :cask, :no_api do
    cmd = described_class.new(["with-depends-on-everything"])
    cask = instance_double(Cask::Cask, full_name: "with-depends-on-everything",
                                       to_s:      "with-depends-on-everything")
    tab = instance_double(Cask::Tab, runtime_dependencies: {
      "cask"    => [{ "full_name" => "local-caffeine" }],
      "formula" => [{ "full_name" => "unar" }],
    })
    HOMEBREW_CELLAR.mkpath
    allow(cmd.args.named).to receive(:to_resolved_formulae_to_casks).and_return([[], [cask]].map(&:freeze).freeze)
    allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(tab)

    expect { cmd.run }
      .to output("local-caffeine unar\n").to_stdout

    expect(Homebrew).to have_failed
  end
end
