# frozen_string_literal: true

require "formula_installer"
require "test/support/fixtures/testball"

RSpec.describe FormulaInstaller do
  include FileUtils

  subject(:keg) { described_class.new(keg_path) }

  describe "#fresh_install" do
    subject(:formula_installer) { described_class.new(Testball.new) }

    it "is true by default" do
      formula = Testball.new
      expect(formula_installer.fresh_install?(formula)).to be true
    end

    it "is false in developer mode" do
      formula = Testball.new
      allow(Homebrew::EnvConfig).to receive_messages(developer?: true)
      expect(formula_installer.fresh_install?(formula)).to be false
    end
  end
end
