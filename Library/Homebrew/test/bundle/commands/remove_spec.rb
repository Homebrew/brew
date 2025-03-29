# frozen_string_literal: true

require "bundle"
require "bundle/commands/remove"
require "cask/cask_loader"

RSpec.describe Homebrew::Bundle::Commands::Remove do
  subject(:remove) do
    described_class.run(*args, type:, global:, file:)
  end

  before { File.write(file, content) }
  after { FileUtils.rm_f file }

  let(:global) { false }

  context "when called with a valid formula" do
    let(:args) { ["hello"] }
    let(:type) { :brew }
    let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }
    let(:content) do
      <<~BREWFILE
        brew "hello"
      BREWFILE
    end

    before do
      stub_formula_loader formula("hello") { url "hello-1.0" }
    end

    it "removes entries from the given Brewfile" do
      expect { remove }.not_to raise_error
      expect(File.read(file)).not_to include("#{type} \"#{args.first}\"")
    end
  end

  context "when called with no type" do
    let(:args) { ["foo"] }
    let(:type) { :none }
    let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }
    let(:content) do
      <<~BREWFILE
        tap "someone/tap"
        brew "foo"
        cask "foo"
      BREWFILE
    end

    it "removes all matching entries from the given Brewfile" do
      expect { remove }.not_to raise_error
      expect(File.read(file)).not_to include(args.first)
    end

    context "with arguments that match entries only when considering formula aliases" do
      let(:foo) do
        instance_double(
          Formula,
          name:      "foo",
          full_name: "qux/quuz/foo",
          oldnames:  ["oldfoo"],
          aliases:   ["foobar"],
        )
      end
      let(:args) { ["foobar"] }

      it "suggests using `--formula` to match against formula aliases" do
        expect(Formulary).to receive(:factory).with("foobar").and_return(foo)
        expect { remove }.not_to raise_error
        expect(File.read(file)).to eq(content)
        # FIXME: Why doesn't this work?
        # expect { remove }.to output("--formula").to_stderr
      end
    end
  end
end
