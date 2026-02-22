# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/uv_checker"
require "bundle/uv_installer"

RSpec.describe Homebrew::Bundle::Checker::UvChecker do
  subject(:checker) { described_class.new }

  describe "#installed_and_up_to_date?" do
    it "returns false when package is not installed" do
      allow(Homebrew::Bundle::UvInstaller).to receive(:package_installed?).and_return(false)
      expect(
        checker.installed_and_up_to_date?(
          { name: "mkdocs", options: { specifier: "<2.0", with: ["mkdocs-material<10"] } },
        ),
      ).to be(false)
    end

    it "returns true when package and options match" do
      expect(Homebrew::Bundle::UvInstaller).to receive(:package_installed?)
        .with("mkdocs", specifier: "<2.0", with: ["mkdocs-material<10"])
        .and_return(true)

      expect(
        checker.installed_and_up_to_date?(
          { name: "mkdocs", options: { specifier: "<2.0", with: ["mkdocs-material<10"] } },
        ),
      ).to be(true)
    end
  end

  describe "#failure_reason" do
    it "returns a package-specific message" do
      expect(
        checker.failure_reason({ name: "mkdocs", options: { specifier: "<2.0" } }, no_upgrade: false),
      ).to eq("uv Tool mkdocs needs to be installed.")
    end
  end

  describe "#find_actionable" do
    let(:entries) do
      [
        Homebrew::Bundle::Dsl::Entry.new(:uv, "ruff"),
        Homebrew::Bundle::Dsl::Entry.new(:uv, "mkdocs", specifier: "<2.0", with: ["mkdocs-material<10"]),
        Homebrew::Bundle::Dsl::Entry.new(:brew, "wget"),
      ]
    end

    it "checks uv entries and passes normalized options to installer checks" do
      expect(Homebrew::Bundle::UvInstaller).to receive(:package_installed?)
        .with("ruff", specifier: nil, with: [])
        .and_return(true)
      expect(Homebrew::Bundle::UvInstaller).to receive(:package_installed?)
        .with("mkdocs", specifier: "<2.0", with: ["mkdocs-material<10"])
        .and_return(true)

      actionable = checker.find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
      expect(actionable).to eq([])
    end

    it "returns missing uv tools from full check flow" do
      allow(Homebrew::Bundle::UvInstaller).to receive(:package_installed?) do |name, **|
        name == "ruff"
      end

      actionable = checker.find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
      expect(actionable).to eq(["uv Tool mkdocs needs to be installed."])
    end
  end
end
