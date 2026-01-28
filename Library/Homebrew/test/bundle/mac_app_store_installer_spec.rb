# frozen_string_literal: true

require "bundle"
require "bundle/mac_app_store_installer"

RSpec.describe Homebrew::Bundle::MacAppStoreInstaller do
  before do
    stub_formula_loader formula("mas") { url "mas-1.0" }
  end

  describe ".installed_app_ids" do
    it "shells out" do
      expect { described_class.installed_app_ids }.not_to raise_error
    end
  end

  describe ".app_id_installed_and_up_to_date?" do
    it "returns result" do
      allow(described_class).to receive_messages(installed_app_ids: [123, 456], outdated_app_ids: [456])
      expect(described_class.app_id_installed_and_up_to_date?(123)).to be(true)
      expect(described_class.app_id_installed_and_up_to_date?(456)).to be(false)
    end
  end

  context "when mas is not installed" do
    before do
      allow(Homebrew::Bundle).to receive(:mas_installed?).and_return(false)
    end

    it "tries to install mas" do
      expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "install", "mas",
                                                        verbose: false).and_return(true)
      expect { described_class.preinstall!("foo", 123) }.to raise_error(RuntimeError)
    end

    describe ".outdated_app_ids" do
      it "does not shell out" do
        expect(described_class).not_to receive(:`)
        described_class.reset!
        described_class.outdated_app_ids
      end
    end
  end

  context "when mas is installed" do
    before do
      allow(Homebrew::Bundle).to receive(:mas_installed?).and_return(true)
    end

    describe ".outdated_app_ids" do
      it "returns app ids" do
        expect(described_class).to receive(:`).and_return("foo 123")
        described_class.reset!
        described_class.outdated_app_ids
      end
    end

    context "when app is installed" do
      before do
        allow(described_class).to receive(:installed_app_ids).and_return([123])
      end

      it "skips" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("foo", 123)).to be(false)
      end
    end

    context "when app is outdated" do
      before do
        allow(described_class).to receive_messages(installed_app_ids: [123], outdated_app_ids: [123])
      end

      it "upgrades" do
        expect(Homebrew::Bundle).to receive(:system).with("mas", "upgrade", "123", verbose: false).and_return(true)
        expect(described_class.preinstall!("foo", 123)).to be(true)
        expect(described_class.install!("foo", 123)).to be(true)
      end
    end

    context "when app is not installed" do
      before do
        allow(described_class).to receive(:installed_app_ids).and_return([])
      end

      it "installs app" do
        expect(Homebrew::Bundle).to receive(:system).with("mas", "install", "123", verbose: false).and_return(true)
        expect(described_class.preinstall!("foo", 123)).to be(true)
        expect(described_class.install!("foo", 123)).to be(true)
      end
    end
  end
end
