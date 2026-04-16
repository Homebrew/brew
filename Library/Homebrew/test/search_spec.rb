# typed: false
# frozen_string_literal: true

require "search"
require "descriptions"
require "cmd/desc"

RSpec.describe Homebrew::Search do
  describe "#query_regexp" do
    it "correctly parses a regex query" do
      expect(described_class.query_regexp("/^query$/")).to eq(/^query$/)
    end

    it "returns the original string if it is not a regex query" do
      expect(described_class.query_regexp("query")).to eq("query")
    end

    it "raises an error if the query is an invalid regex" do
      expect { described_class.query_regexp("/+/") }.to raise_error(/not a valid regex/)
    end
  end

  describe "#search" do
    let(:collection) { ["with-dashes", "with@alpha", "with+plus"] }

    context "when given a block" do
      let(:collection) { [["with-dashes", "withdashes"]] }

      it "searches by the selected argument" do
        expect(described_class.search(collection, /withdashes/) { |_, short_name| short_name }).not_to be_empty
        expect(described_class.search(collection, /withdashes/) { |long_name, _| long_name }).to be_empty
      end
    end

    context "when given a regex" do
      it "does not simplify strings" do
        expect(described_class.search(collection, /with-dashes/)).to eq ["with-dashes"]
      end
    end

    context "when given a string" do
      it "simplifies both the query and searched strings" do
        expect(described_class.search(collection, "with dashes")).to eq ["with-dashes"]
      end

      it "does not simplify strings with @ and + characters" do
        expect(described_class.search(collection, "with@alpha")).to eq ["with@alpha"]
        expect(described_class.search(collection, "with+plus")).to eq ["with+plus"]
      end
    end

    context "when searching a Hash" do
      let(:collection) { { "foo" => "bar" } }

      it "returns a Hash" do
        expect(described_class.search(collection, "foo")).to eq "foo" => "bar"
      end

      context "with a nil value" do
        let(:collection) { { "foo" => nil } }

        it "does not raise an error" do
          expect(described_class.search(collection, "foo")).to eq "foo" => nil
        end
      end
    end
  end

  describe "#search_formulae" do
    let(:tab) { instance_double(Tab, installed_on_request: false, installed_as_dependency: false) }
    let(:formula) do
      instance_double(Formula, full_name: "testball", any_version_installed?: false,
                              valid_platform?: true, deprecated?: false, disabled?: false,
                              pinned?: false, requirements: [], deps: [],
                              runtime_installed_formula_dependents: [], stable: nil, head: nil, pour_bottle?: true)
    end

    before do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(Formula).to receive_messages(full_names: ["testball"], alias_full_names: [])
      allow(Formulary).to receive(:factory).with("testball").and_return(formula)
      allow(Tab).to receive(:for_formula).with(formula).and_return(tab)
    end

    it "annotates deprecated formulae" do
      allow(formula).to receive(:deprecated?).and_return(true)
      expect(described_class.search_formulae(/testball/)).to contain_exactly(match(/\(deprecated\)/))
    end

    it "annotates disabled formulae" do
      allow(formula).to receive(:disabled?).and_return(true)
      expect(described_class.search_formulae(/testball/)).to contain_exactly(match(/\(disabled\)/))
    end

    it "does not annotate normal formulae" do
      expect(described_class.search_formulae(/testball/)).to eq(["testball"])
    end

    it "shows only the installed icon for installed formulae" do
      allow(formula).to receive_messages(any_version_installed?: true, pinned?: true)

      expect(described_class.search_formulae(/testball/))
        .to eq([described_class.pretty_installed("testball")])
    end
  end

  describe "#search_casks" do
    let(:depends_on) { instance_double(Cask::DSL::DependsOn, formula: [], cask: []) }
    let(:tab) { instance_double(Cask::Tab, installed_on_request: false, installed_as_dependency: false) }
    let(:cask) do
      instance_double(Cask::Cask, full_name: "testball", installed?: false, deprecated?: false, disabled?: false,
                                   supports_linux?: true, depends_on:)
    end

    before do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(Tap).to receive(:each_with_object).and_return(["testball"])
      allow(Cask::CaskLoader).to receive(:load).with("testball").and_return(cask)
      allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(tab)
    end

    it "annotates deprecated casks", :needs_macos do
      allow(cask).to receive(:deprecated?).and_return(true)
      expect(described_class.search_casks(/testball/)).to contain_exactly(match(/\(deprecated\)/))
    end

    it "annotates disabled casks", :needs_macos do
      allow(cask).to receive(:disabled?).and_return(true)
      expect(described_class.search_casks(/testball/)).to contain_exactly(match(/\(disabled\)/))
    end

    it "does not annotate normal casks", :needs_macos do
      expect(described_class.search_casks(/testball/)).to eq(["testball"])
    end

    it "hides macOS-only casks on Linux", :needs_linux do
      allow(cask).to receive(:supports_linux?).and_return(false)

      expect(described_class.search_casks(/testball/)).to eq([])
    end

    it "shows only the installed icon for installed casks", :needs_macos do
      allow(cask).to receive(:installed?).and_return(true)

      expect(described_class.search_casks(/testball/))
        .to eq([described_class.pretty_installed("testball")])
    end
  end

  describe "#search_descriptions" do
    let(:args) { Homebrew::Cmd::Desc.new(["min_arg_placeholder"]).args }

    context "with api" do
      let(:api_formulae) do
        { "testball" => { "desc" => "Some test" } }
      end

      let(:api_casks) do
        { "testball" => { "desc" => "Some test", "name" => ["Test Ball"] } }
      end

      before do
        allow(Homebrew::API::Formula).to receive(:all_formulae).and_return(api_formulae)
        allow(Homebrew::API::Cask).to receive(:all_casks).and_return(api_casks)
      end

      it "searches formula descriptions" do
        expect { described_class.search_descriptions(described_class.query_regexp("some"), args) }
          .to output(/testball: Some test/).to_stdout
      end

      it "searches cask descriptions", :needs_macos do
        expect { described_class.search_descriptions(described_class.query_regexp("ball"), args) }
          .to output(/testball: \(Test Ball\) Some test/).to_stdout
          .and not_to_output(/testball: Some test/).to_stdout
      end
    end
  end
end
