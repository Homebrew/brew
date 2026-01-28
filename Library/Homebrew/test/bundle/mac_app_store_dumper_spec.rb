# frozen_string_literal: true

require "bundle"
require "bundle/mac_app_store_dumper"

RSpec.describe Homebrew::Bundle::MacAppStoreDumper do
  subject(:dumper) { described_class }

  context "when mas is not installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:mas_installed?).and_return(false)
    end

    it "returns empty list" do
      expect(dumper.apps).to be_empty
    end

    it "dumps as empty string" do # rubocop:todo RSpec/AggregateExamples
      expect(dumper.dump).to eql("")
    end
  end

  context "when there is no apps" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:mas_installed?).and_return(true)
      allow(described_class).to receive(:`).and_return("")
    end

    it "returns empty list" do
      expect(dumper.apps).to be_empty
    end

    it "dumps as empty string" do # rubocop:todo RSpec/AggregateExamples
      expect(dumper.dump).to eql("")
    end
  end

  context "when apps `foo`, `bar` and `baz` are installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:mas_installed?).and_return(true)
      allow(described_class).to receive(:`).and_return("123 foo (1.0)\n456 bar (2.0)\n789 baz (3.0)")
    end

    it "returns list %w[foo bar baz]" do
      expect(dumper.apps).to eql([["123", "foo"], ["456", "bar"], ["789", "baz"]])
    end
  end

  context "when apps `foo`, `bar`, `baz` and `qux` are installed including right-justified IDs" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:mas_installed?).and_return(true)
      allow(described_class).to receive(:`).and_return("123 foo (1.0)\n456 bar (2.0)\n789 baz (3.0)")
      allow(described_class).to receive(:`).and_return("123 foo (1.0)\n456 bar (2.0)\n789 baz (3.0)\n 10 qux (4.0)")
    end

    it "returns list %w[foo bar baz qux]" do
      expect(dumper.apps).to eql([["123", "foo"], ["456", "bar"], ["789", "baz"], ["10", "qux"]])
    end
  end

  context "with invalid app details" do
    let(:invalid_mas_output) do
      <<~HEREDOC
        497799835 Xcode (9.2)
        425424353 The Unarchiver (4.0.0)
        08981434 iMovie (10.1.8)
        409201541 Pages (7.1)
        123456789 123AppNameWithNumbers (1.0)
        409203825 Numbers (5.1)
        944924917 Pastebin It! (1.0)
        123456789 My (cool) app (1.0)
        987654321 an-app-i-use (2.1)
        123457867 App name with many spaces (1.0)
        893489734 my,comma,app (2.2)
        832423434 another_app_name (1.0)
        543213432 My App? (1.0)
        688963445 app;with;semicolons (1.0)
        123345384 my 😊 app (2.0)
        896732467 你好 (1.1)
        634324555 مرحبا (1.0)
        234324325 áéíóú (1.0)
        310633997 non>‎<printing>⁣<characters (1.0)
      HEREDOC
    end

    let(:expected_app_details_array) do
      [
        ["497799835", "Xcode"],
        ["425424353", "The Unarchiver"],
        ["08981434", "iMovie"],
        ["409201541", "Pages"],
        ["123456789", "123AppNameWithNumbers"],
        ["409203825", "Numbers"],
        ["944924917", "Pastebin It!"],
        ["123456789", "My (cool) app"],
        ["987654321", "an-app-i-use"],
        ["123457867", "App name with many spaces"],
        ["893489734", "my,comma,app"],
        ["832423434", "another_app_name"],
        ["543213432", "My App?"],
        ["688963445", "app;with;semicolons"],
        ["123345384", "my 😊 app"],
        ["896732467", "你好"],
        ["634324555", "مرحبا"],
        ["234324325", "áéíóú"],
        ["310633997", "non><printing><characters"],
      ]
    end

    let(:expected_mas_dumped_output) do
      <<~HEREDOC
        mas "123AppNameWithNumbers", id: 123456789
        mas "an-app-i-use", id: 987654321
        mas "another_app_name", id: 832423434
        mas "App name with many spaces", id: 123457867
        mas "app;with;semicolons", id: 688963445
        mas "iMovie", id: 08981434
        mas "My (cool) app", id: 123456789
        mas "My App?", id: 543213432
        mas "my 😊 app", id: 123345384
        mas "my,comma,app", id: 893489734
        mas "non><printing><characters", id: 310633997
        mas "Numbers", id: 409203825
        mas "Pages", id: 409201541
        mas "Pastebin It!", id: 944924917
        mas "The Unarchiver", id: 425424353
        mas "Xcode", id: 497799835
        mas "áéíóú", id: 234324325
        mas "مرحبا", id: 634324555
        mas "你好", id: 896732467
      HEREDOC
    end

    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:mas_installed?).and_return(true)
      allow(described_class).to receive(:`).and_return(invalid_mas_output)
    end

    it "returns only valid apps" do
      expect(dumper.apps).to eql(expected_app_details_array)
    end

    it "dumps excluding invalid apps" do # rubocop:todo RSpec/AggregateExamples
      expect(dumper.dump).to eq(expected_mas_dumped_output.strip)
    end
  end

  context "with the new format after mas-cli/mas#339" do
    let(:new_mas_output) do
      <<~HEREDOC
        1440147259  AdGuard for Safari  (1.9.13)
        497799835   Xcode               (12.5)
        425424353   The Unarchiver      (4.3.1)
      HEREDOC
    end

    let(:expected_app_details_array) do
      [
        ["1440147259", "AdGuard for Safari"],
        ["497799835", "Xcode"],
        ["425424353", "The Unarchiver"],
      ]
    end

    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:mas_installed?).and_return(true)
      allow(described_class).to receive(:`).and_return(new_mas_output)
    end

    it "parses the app names without trailing whitespace" do
      expect(dumper.apps).to eql(expected_app_details_array)
    end
  end
end
