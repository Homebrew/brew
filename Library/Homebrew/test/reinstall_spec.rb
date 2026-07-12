# typed: strict
# frozen_string_literal: true

require "reinstall"

RSpec.describe Homebrew::Reinstall do
  describe ".build_install_context" do
    it "leaves the current keg in place until reinstalling", :integration_test do
      setup_test_formula "testball", tab_attributes: { installed_on_request: true }
      formula = Formula["testball"]
      keg = Keg.new(formula.prefix)
      keg.link

      context = described_class.build_install_context(formula, flags: [])

      expect(context.keg&.to_s).to eq(keg.to_s)
      expect(context.link_keg).to be(true)
      expect(formula.prefix).to exist
      expect(formula.opt_prefix).to be_a_directory
      expect(Pathname.new("#{keg}.reinstall")).not_to exist
    end
  end

  describe ".reinstall_formula" do
    it "restores and relinks a backup keg when reinstalling fails", :integration_test do
      setup_test_formula "testball", tab_attributes: { installed_on_request: true }
      formula = Formula["testball"]
      keg = Keg.new(formula.prefix)
      (keg/"bin").mkpath
      (keg/"bin/test").write("current")
      keg.link

      context = described_class.build_install_context(formula, flags: [])
      allow(context.formula_installer).to receive(:install).and_raise(RuntimeError, "boom")

      expect { described_class.reinstall_formula(context) }.to raise_error(RuntimeError, "boom")

      expect((keg/"bin/test").read).to eq("current")
      expect(keg.linked?).to be(true)
    end

    it "does not back up the keg when reinstall was already attempted", :integration_test do
      setup_test_formula "testball", tab_attributes: { installed_on_request: true }
      formula = Formula["testball"]
      keg = Keg.new(formula.prefix)
      (keg/"bin").mkpath
      (keg/"bin/test").write("current")
      keg.link

      FormulaInstaller.attempted << formula
      context = described_class.build_install_context(formula, flags: [])

      described_class.reinstall_formula(context)

      expect((keg/"bin/test").read).to eq("current")
      expect(keg.linked?).to be(true)
      expect(Pathname.new("#{keg}.reinstall")).not_to exist
    ensure
      FormulaInstaller.clear_attempted
    end
  end

  describe ".backup" do
    it "removes a stale reinstall backup keg" do
      keg_path = HOMEBREW_CELLAR/"testball/0.1"
      (keg_path/"bin").mkpath
      keg = Keg.new(keg_path)
      backup = Pathname.new("#{keg}.reinstall")

      (keg_path/"bin/test").write("current")
      (backup/"bin").mkpath
      (backup/"bin/test").write("stale")

      described_class.send(:backup, keg)

      expect(keg_path).not_to exist
      expect(backup/"bin/test").to exist
      expect((backup/"bin/test").read).to eq("current")
    end
  end
end
