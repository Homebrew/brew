# typed: true
# frozen_string_literal: true

require "cmd/desc"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Desc do
  it_behaves_like "parseable arguments"

  it "shows a given Formula's description", :integration_test do
    setup_test_formula "testball"

    expect { brew "desc", "testball" }
      .to output("testball: Some test\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "shows an installed Cask's description with status" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    cask = Cask::Cask.new("local-transmission") do
      version "2.61"
      name "Transmission"
      desc "BitTorrent client"
      url "https://example.com/local-transmission.zip"
    end
    cmd = described_class.new(["--cask", "local-transmission"])

    allow(cmd.args.named).to receive(:to_formulae_and_casks).and_return([cask])
    allow(Cask::Caskroom).to receive(:casks).and_return([cask])
    allow(Formulary).to receive(:factory)
      .with("local-transmission")
      .and_raise(FormulaUnavailableError.new("local-transmission"))
    allow(Cask::CaskLoader).to receive(:load).with("local-transmission").and_return(cask)

    expect { cmd.run }
      .to output(/local-transmission .*✔.*: \(Transmission\) BitTorrent client/).to_stdout
      .and not_to_output.to_stderr
  end

  it "omits a Cask without a description" do
    cask = Cask::Cask.new("no-description") do
      version "1.0"
      name "No Description"
      url "https://example.com/no-description.zip"
    end
    cmd = described_class.new(["--cask", "no-description"])

    allow(cmd.args.named).to receive(:to_formulae_and_casks).and_return([cask])

    expect { cmd.run }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
  end

  it "successfully searches without API by default" do
    expect(Homebrew::Search).to receive(:search_descriptions)
      .with("testball", anything, search_type: Descriptions::SearchField::Either)

    with_env(
      "HOMEBREW_NO_INSTALL_FROM_API"  => "1",
      "HOMEBREW_REQUIRE_TAP_TRUST"    => nil,
      "HOMEBREW_NO_REQUIRE_TAP_TRUST" => nil,
    ) do
      expect { described_class.new(["--search", "testball"]).run }
        .to not_to_output.to_stderr
    end
  end

  it "successfully searches with --search and HOMEBREW_NO_REQUIRE_TAP_TRUST" do
    expect(Homebrew::Search).to receive(:search_descriptions)
      .with("ball", anything, search_type: Descriptions::SearchField::Either)

    expect { with_env(HOMEBREW_NO_REQUIRE_TAP_TRUST: "1") { described_class.new(["--search", "ball"]).run } }
      .to not_to_output.to_stderr
  end

  it "successfully searches with --search and HOMEBREW_REQUIRE_TAP_TRUST" do
    expect(Homebrew::Search).to receive(:search_descriptions)
      .with("ball", anything, search_type: Descriptions::SearchField::Either)

    expect { with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1") { described_class.new(["--search", "ball"]).run } }
      .to not_to_output.to_stderr
  end

  it "successfully searches with API" do
    expect(Homebrew::Search).to receive(:search_descriptions)
      .with("testball", anything, search_type: Descriptions::SearchField::Either)

    expect { described_class.new(["--search", "testball"]).run }
      .to not_to_output.to_stderr
  end
end
