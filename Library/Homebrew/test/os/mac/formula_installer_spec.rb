# typed: false
# frozen_string_literal: true

require "formula_installer"
require "test/support/fixtures/testball"

RSpec.describe FormulaInstaller do
  subject(:keg) { described_class.new(keg_path) }

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
end
