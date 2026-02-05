# frozen_string_literal: true

require "bundle"
require "bundle/vscode_extension_dumper"

RSpec.describe Homebrew::Bundle::VscodeExtensionDumper do
  subject(:dumper) { described_class }

  context "when vscode is not installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:vscode_installed?).and_return(false)
      allow(described_class).to receive(:`).and_return("")
    end

    it "returns an empty list" do
      expect(dumper.extensions).to be_empty
    end

    it "dumps an empty string" do # rubocop:todo RSpec/AggregateExamples
      expect(dumper.dump).to eql("")
    end
  end

  context "when vscode is installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:which_vscode).and_return(Pathname.new("code"))
    end

    it "returns package list" do
      output = <<~EOF
        catppuccin.catppuccin-vsc
        davidanson.vscode-markdownlint
        streetsidesoftware.code-spell-checker
        tamasfe.even-better-toml
      EOF

      allow(described_class).to receive(:`)
        .with('"code" --list-extensions 2>/dev/null')
        .and_return(output)
      expect(dumper.extensions).to eql([
        "catppuccin.catppuccin-vsc",
        "davidanson.vscode-markdownlint",
        "streetsidesoftware.code-spell-checker",
        "tamasfe.even-better-toml",
      ])
    end
  end
end
