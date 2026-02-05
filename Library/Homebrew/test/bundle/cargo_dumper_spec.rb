# frozen_string_literal: true

require "bundle"
require "bundle/cargo_dumper"

RSpec.describe Homebrew::Bundle::CargoDumper do
  subject(:dumper) { described_class }

  context "when cargo is not installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:cargo_installed?).and_return(false)
    end

    it "returns an empty list" do
      expect(dumper.packages).to be_empty
    end

    it "dumps an empty string" do # rubocop:todo RSpec/AggregateExamples
      expect(dumper.dump).to eql("")
    end
  end

  context "when cargo is installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive_messages(cargo_installed?: true, which_cargo: Pathname.new("cargo"))
    end

    it "returns package list" do
      allow(described_class).to receive(:`).with("cargo install --list").and_return(<<~EOS)
        ripgrep v13.0.0:
            rg
        bat v0.24.0 (/Users/test/.cargo/bin/bat)
      EOS

      expect(dumper.packages).to eql(%w[ripgrep bat])
    end

    it "dumps package list" do
      allow(dumper).to receive(:packages).and_return(["ripgrep", "bat"])
      expect(dumper.dump).to eql("cargo \"ripgrep\"\ncargo \"bat\"")
    end
  end
end
