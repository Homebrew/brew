# frozen_string_literal: true

require "bundle"
require "bundle/uv_dumper"

RSpec.describe Homebrew::Bundle::UvDumper do
  subject(:dumper) { described_class }

  let(:uv_tool_list_command) do
    [
      "uv tool list",
      "--show-version-specifiers",
      "--show-with",
      "--show-extras",
      "2>/dev/null",
    ].join(" ")
  end

  context "when uv is not installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:uv_installed?).and_return(false)
    end

    it "returns empty packages and dump output" do
      expect(dumper.packages).to be_empty
      expect(dumper.dump).to eql("")
    end
  end

  context "when uv is installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive_messages(uv_installed?: true, which_uv: Pathname.new("uv"))
    end

    it "returns normalized package entries sorted by package name" do
      allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
        ruff v0.14.14 [required: <0.15]
        - ruff
        mkdocs v1.6.1 [with: mkdocs-material<10]
        - mkdocs
      OUTPUT

      expect(dumper.packages).to eql([
        {
          name:      "mkdocs",
          specifier: nil,
          with:      ["mkdocs-material<10"],
        },
        {
          name:      "ruff",
          specifier: "<0.15",
          with:      [],
        },
      ])
    end

    it "dumps correct Brewfile entries" do
      allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
        ruff v0.14.14 [required: <0.15] [with: httpx>=0.27]
        - ruff
      OUTPUT

      expect(dumper.dump).to eql('uv "ruff", specifier: "<0.15", with: ["httpx>=0.27"]')
    end

    it "dumps specifier-only Brewfile entries" do
      allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
        ruff v0.14.14 [required: <0.15]
        - ruff
      OUTPUT

      expect(dumper.dump).to eql('uv "ruff", specifier: "<0.15"')
    end

    it "handles tools with no optional metadata" do
      allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
        ruff v0.14.14
        - ruff
      OUTPUT

      expect(dumper.dump).to eql('uv "ruff"')
    end

    it "returns empty packages when no tools are installed" do
      allow(described_class).to receive(:`).with(uv_tool_list_command).and_return("")

      expect(dumper.packages).to be_empty
      expect(dumper.dump).to eql("")
    end

    it "handles multiple with dependencies" do
      allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
        mkdocs v1.6.1 [with: mkdocs-material, mkdocs-awesome-page-plugin]
        - mkdocs
      OUTPUT

      expect(dumper.packages.first&.dig(:with)).to eql(["mkdocs-awesome-page-plugin", "mkdocs-material"])
    end

    it "keeps comma-constrained with requirements as a single requirement" do
      allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
        ruff v0.14.14 [with: httpx>=0.27, <0.29]
        - ruff
      OUTPUT

      expect(dumper.packages.first&.dig(:with)).to eql(["httpx>=0.27, <0.29"])
      expect(dumper.dump).to eql('uv "ruff", with: ["httpx>=0.27, <0.29"]')
    end

    it "preserves extras for the main tool requirement" do
      allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
        fastapi v0.129.0 [extras: all, standard]
        - fastapi
      OUTPUT

      expect(dumper.packages.first).to include(name: "fastapi[all,standard]")
      expect(dumper.dump).to eql('uv "fastapi[all,standard]"')
    end
  end
end
