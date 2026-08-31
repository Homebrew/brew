# typed: true
# frozen_string_literal: true

require "formula_installer"
require "test/support/fixtures/testball"

RSpec.describe FormulaInstaller do
  include FileUtils

  describe "#fresh_install" do
    subject(:formula_installer) { described_class.new(Testball.new) }

    it "is true when non-developer and non-outdated" do
      formula = Testball.new
      allow(Homebrew::EnvConfig).to receive_messages(developer?: false)
      allow(OS::Mac.version).to receive_messages(outdated_release?: false)
      expect(formula_installer.fresh_install?(formula)).to be true
    end

    it "is false in developer mode" do
      formula = Testball.new
      allow(Homebrew::EnvConfig).to receive_messages(developer?: true)
      allow(OS::Mac.version).to receive_messages(outdated_release?: false)
      expect(formula_installer.fresh_install?(formula)).to be false
    end

    it "is false on outdated releases" do
      formula = Testball.new
      allow(Homebrew::EnvConfig).to receive_messages(developer?: false)
      allow(OS::Mac.version).to receive_messages(outdated_release?: true)
      expect(formula_installer.fresh_install?(formula)).to be false
    end
  end

  describe "#source_install_guidance" do
    subject(:formula_installer) { described_class.new(Testball.new) }

    it "mentions the Intel bottle phase-out and policy discussion on Intel macOS" do
      allow(Hardware::CPU).to receive_messages(intel?: true)

      guidance = formula_installer.source_install_guidance(Testball.new)
      expect(guidance).to include("Homebrew bottles are being phased out for Intel macOS.")
      expect(guidance).to include("https://github.com/orgs/Homebrew/discussions/7044")
    end

    it "falls back to the default guidance on Apple Silicon" do
      allow(Hardware::CPU).to receive_messages(intel?: false)

      guidance = formula_installer.source_install_guidance(Testball.new)
      expect(guidance).to include("If you're feeling brave, you can try to install from source with:")
    end
  end
end
