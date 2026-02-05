# frozen_string_literal: true

require "bundle"
require "bundle/cask_dumper"
require "bundle/cask_installer"

RSpec.describe Homebrew::Bundle::CaskInstaller do
  describe ".installed_casks" do
    before do
      Homebrew::Bundle::CaskDumper.reset!
    end

    it "shells out" do
      expect { described_class.installed_casks }.not_to raise_error
    end
  end

  describe ".cask_installed_and_up_to_date?" do
    it "returns result" do
      described_class.reset!
      allow(described_class).to receive_messages(installed_casks: ["foo", "baz"],
                                                 outdated_casks:  ["baz"])
      expect(described_class.cask_installed_and_up_to_date?("foo")).to be(true)
      expect(described_class.cask_installed_and_up_to_date?("baz")).to be(false)
    end
  end

  context "when brew-cask is not installed" do
    describe ".outdated_casks" do
      it "returns empty array" do
        described_class.reset!
        expect(described_class.outdated_casks).to eql([])
      end
    end
  end

  context "when brew-cask is installed" do
    before do
      Homebrew::Bundle::CaskDumper.reset!
      allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
    end

    describe ".outdated_casks" do
      it "returns empty array" do
        described_class.reset!
        expect(described_class.outdated_casks).to eql([])
      end
    end

    context "when cask is installed" do
      before do
        Homebrew::Bundle::CaskDumper.reset!
        allow(described_class).to receive(:installed_casks).and_return(["google-chrome"])
      end

      it "skips" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("google-chrome")).to be(false)
      end
    end

    context "when cask is outdated" do
      before do
        allow(described_class).to receive_messages(installed_casks: ["google-chrome"],
                                                   outdated_casks:  ["google-chrome"])
      end

      it "upgrades" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "upgrade", "--cask", "google-chrome", verbose: false)
                          .and_return(true)
        expect(described_class.preinstall!("google-chrome")).to be(true)
        expect(described_class.install!("google-chrome")).to be(true)
      end
    end

    context "when cask is outdated and uses auto-update" do
      before do
        described_class.reset!
        allow(Homebrew::Bundle::CaskDumper).to receive_messages(cask_names: ["opera"], outdated_cask_names: [])
        allow(Homebrew::Bundle::CaskDumper).to receive(:cask_is_outdated_using_greedy?).with("opera").and_return(true)
      end

      it "upgrades" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "upgrade", "--cask", "opera", verbose: false)
                          .and_return(true)
        expect(described_class.preinstall!("opera", greedy: true)).to be(true)
        expect(described_class.install!("opera", greedy: true)).to be(true)
      end
    end

    context "when cask is not installed" do
      before do
        allow(described_class).to receive(:installed_casks).and_return([])
      end

      it "installs cask" do
        expect(Homebrew::Bundle).to receive(:brew).with("install", "--cask", "google-chrome", "--adopt",
                                                        verbose: false)
                                                  .and_return(true)
        expect(described_class.preinstall!("google-chrome")).to be(true)
        expect(described_class.install!("google-chrome")).to be(true)
      end

      it "installs cask with arguments" do
        expect(Homebrew::Bundle).to(
          receive(:brew).with("install", "--cask", "firefox", "--appdir=/Applications", "--adopt",
                              verbose: false)
                          .and_return(true),
        )
        expect(described_class.preinstall!("firefox", args: { appdir: "/Applications" })).to be(true)
        expect(described_class.install!("firefox", args: { appdir: "/Applications" })).to be(true)
      end

      it "reports a failure" do
        expect(Homebrew::Bundle).to receive(:brew).with("install", "--cask", "google-chrome", "--adopt",
                                                        verbose: false)
                                                  .and_return(false)
        expect(described_class.preinstall!("google-chrome")).to be(true)
        expect(described_class.install!("google-chrome")).to be(false)
      end

      context "with boolean arguments" do
        it "includes a flag if true" do
          expect(Homebrew::Bundle).to receive(:brew).with("install", "--cask", "iterm", "--force",
                                                          verbose: false)
                                                    .and_return(true)
          expect(described_class.preinstall!("iterm", args: { force: true })).to be(true)
          expect(described_class.install!("iterm", args: { force: true })).to be(true)
        end

        it "does not include a flag if false" do
          expect(Homebrew::Bundle).to receive(:brew).with("install", "--cask", "iterm", "--adopt", verbose: false)
                                                    .and_return(true)
          expect(described_class.preinstall!("iterm", args: { force: false })).to be(true)
          expect(described_class.install!("iterm", args: { force: false })).to be(true)
        end
      end
    end

    context "when the postinstall option is provided" do
      before do
        Homebrew::Bundle::CaskDumper.reset!
        allow(Homebrew::Bundle::CaskDumper).to receive_messages(cask_names:          ["google-chrome"],
                                                                outdated_cask_names: ["google-chrome"])
        allow(Homebrew::Bundle).to receive(:brew).and_return(true)
        allow(described_class).to receive(:upgrading?).and_return(true)
      end

      it "runs the postinstall command" do
        expect(Kernel).to receive(:system).with("custom command").and_return(true)
        expect(described_class.preinstall!("google-chrome", postinstall: "custom command")).to be(true)
        expect(described_class.install!("google-chrome", postinstall: "custom command")).to be(true)
      end

      it "reports a failure when postinstall fails" do
        expect(Kernel).to receive(:system).with("custom command").and_return(false)
        expect(described_class.preinstall!("google-chrome", postinstall: "custom command")).to be(true)
        expect(described_class.install!("google-chrome", postinstall: "custom command")).to be(false)
      end
    end
  end
end
