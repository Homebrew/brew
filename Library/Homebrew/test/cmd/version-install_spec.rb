# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/version-install"

RSpec.describe Homebrew::Cmd::VersionInstall do
  subject(:version_install) { described_class.new(args) }

  let(:formulary_factory) { ->(ref, **_opts) { raise FormulaUnavailableError, ref } }
  let(:installed_taps) { [] }
  let(:installed_formula_names) { [] }
  let(:tap_name) { "tester/homebrew-versions" }
  let(:versioned_name) { "#{formula}@#{version}" }
  let(:args) { [formula, version] }
  let(:version) { "1.2" }
  let(:formula) { "foo" }

  before do
    allow(Tap).to receive(:installed).and_return(installed_taps)
    allow(Formula).to receive(:installed_formula_names).and_return(installed_formula_names)
    allow(Homebrew::EnvConfig).to receive(:no_github_api?).and_return(true)
    allow(Formulary).to receive(:factory) { |ref, **opts| formulary_factory.call(ref, **opts) }
  end

  it_behaves_like "parseable arguments"

  context "when the versioned formula is already installed" do
    let(:installed_formula_names) { [versioned_name] }

    it "skips installation" do
      expect(version_install).not_to receive(:safe_system)

      version_install.run
    end
  end

  context "when a tap already contains the versioned formula" do
    let(:existing_tap_name) { "alice/homebrew-versions" }
    let(:existing_tap) do
      instance_double(
        Tap,
        name:                  existing_tap_name,
        formula_files_by_name: { versioned_name => Pathname("/tmp/#{versioned_name}.rb") },
      )
    end
    let(:installed_taps) { [existing_tap] }
    let(:install_target) { "#{existing_tap_name}/#{versioned_name}" }

    before do
      allow(existing_tap).to receive(:to_s).and_return(existing_tap_name)
    end

    it "installs from the existing tap extraction" do
      expect(version_install).to receive(:safe_system)
        .with(HOMEBREW_BREW_FILE, "install", install_target).once

      version_install.run
    end
  end

  context "with formula@version input" do
    let(:args) { ["#{formula}@#{version}"] }
    let(:versioned_formula) { instance_double(Formula, full_name: "homebrew/core/#{versioned_name}") }
    let(:install_target) { "homebrew/core/#{versioned_name}" }
    let(:formulary_factory) do
      lambda do |ref, **_opts|
        return versioned_formula if ref == "#{formula}@#{version}"

        raise FormulaUnavailableError, ref
      end
    end

    it "installs a versioned formula that already exists" do
      expect(version_install).to receive(:safe_system)
        .with(HOMEBREW_BREW_FILE, "install", install_target).once

      version_install.run
    end
  end

  context "when the current formula matches the requested version" do
    let(:current_formula) { instance_double(Formula, full_name: "homebrew/core/#{formula}", name: formula, version:) }
    let(:install_target) { "homebrew/core/#{formula}" }
    let(:formulary_factory) do
      lambda do |ref, **_opts|
        return current_formula if ref == formula
        return raise FormulaUnavailableError, ref if ref == "#{formula}@#{version}"

        raise "Unexpected ref: #{ref}"
      end
    end

    it "installs the current formula" do
      expect(version_install).to receive(:safe_system)
        .with(HOMEBREW_BREW_FILE, "install", install_target).once

      version_install.run
    end

    context "when the current formula is already installed" do
      let(:installed_formula_names) { [formula] }

      it "skips installation" do
        expect(version_install).not_to receive(:safe_system)

        version_install.run
      end
    end
  end

  context "when extracting into a tap" do
    let(:tap_installed) { false }
    let(:tap) { instance_double(Tap, name: tap_name, installed?: tap_installed) }

    before do
      allow(User).to receive(:current).and_return("tester")
      allow(tap).to receive(:to_s).and_return(tap_name)
      allow(Tap).to receive(:fetch).with(tap_name).and_return(tap)
    end

    it "extracts into a new tap when needed" do
      expect(version_install).to receive(:safe_system)
        .with(HOMEBREW_BREW_FILE, "tap-new", "--no-git", tap_name).ordered
      expect(version_install).to receive(:safe_system)
        .with(HOMEBREW_BREW_FILE, "extract", formula, tap_name, "--version=#{version}").ordered
      expect(version_install).to receive(:safe_system)
        .with(HOMEBREW_BREW_FILE, "install", "#{tap_name}/#{versioned_name}").ordered

      version_install.run
    end

    context "when the tap already exists" do
      let(:tap_installed) { true }

      it "skips tap creation" do
        expect(version_install).to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, "extract", formula, tap_name, "--version=#{version}").ordered
        expect(version_install).to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, "install", "#{tap_name}/#{versioned_name}").ordered

        version_install.run
      end
    end
  end
end
