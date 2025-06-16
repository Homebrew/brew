# frozen_string_literal: true

require "bundle"
require "bundle/commands/install"
require "bundle/skipper"

RSpec.describe Homebrew::Bundle::Commands::Install do
  before do
    allow_any_instance_of(IO).to receive(:puts)
  end

  context "when a Brewfile is not found" do
    it "raises an error" do
      allow_any_instance_of(Pathname).to receive(:read).and_raise(Errno::ENOENT)
      expect { described_class.run }.to raise_error(RuntimeError)
    end
  end

  context "when a Brewfile is found", :no_api do
    let(:brewfile_contents) do
      <<~EOS
        tap 'phinze/cask'
        brew 'mysql', conflicts_with: ['mysql56']
        cask 'phinze/cask/google-chrome', greedy: true
        mas '1Password', id: 443987910
        vscode 'GitHub.codespaces'
      EOS
    end

    it "does not raise an error" do
      allow(Homebrew::Bundle::TapInstaller).to receive(:preinstall).and_return(false)
      allow(Homebrew::Bundle::VscodeExtensionInstaller).to receive(:preinstall).and_return(false)
      allow(Homebrew::Bundle::BrewInstaller).to receive_messages(preinstall: true, install: true)
      allow(Homebrew::Bundle::CaskInstaller).to receive_messages(preinstall: true, install: true)
      allow(Homebrew::Bundle::MacAppStoreInstaller).to receive_messages(preinstall: true, install: true)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)
      expect { described_class.run }.not_to raise_error
    end

    it "#dsl returns a valid DSL" do
      allow(Homebrew::Bundle::TapInstaller).to receive(:preinstall).and_return(false)
      allow(Homebrew::Bundle::VscodeExtensionInstaller).to receive(:preinstall).and_return(false)
      allow(Homebrew::Bundle::BrewInstaller).to receive_messages(preinstall: true, install: true)
      allow(Homebrew::Bundle::CaskInstaller).to receive_messages(preinstall: true, install: true)
      allow(Homebrew::Bundle::MacAppStoreInstaller).to receive_messages(preinstall: true, install: true)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)
      described_class.run
      expect(described_class.dsl.entries.first.name).to eql("phinze/cask")
    end

    it "does not raise an error when skippable" do
      expect(Homebrew::Bundle::BrewInstaller).not_to receive(:install)

      allow(Homebrew::Bundle::Skipper).to receive(:skip?).and_return(true)
      allow_any_instance_of(Pathname).to receive(:read)
        .and_return("brew 'mysql'")
      expect { described_class.run }.not_to raise_error
    end

    it "exits on failures" do
      allow(Homebrew::Bundle::BrewInstaller).to receive_messages(preinstall: true, install: false)
      allow(Homebrew::Bundle::CaskInstaller).to receive_messages(preinstall: true, install: false)
      allow(Homebrew::Bundle::MacAppStoreInstaller).to receive_messages(preinstall: true, install: false)
      allow(Homebrew::Bundle::TapInstaller).to receive_messages(preinstall: true, install: false)
      allow(Homebrew::Bundle::VscodeExtensionInstaller).to receive_messages(preinstall: true, install: false)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)

      expect { described_class.run }.to raise_error(SystemExit)
    end

    it "skips installs from failed taps" do
      allow(Homebrew::Bundle::CaskInstaller).to receive(:preinstall).and_return(false)
      allow(Homebrew::Bundle::TapInstaller).to receive_messages(preinstall: true, install: false)
      allow(Homebrew::Bundle::BrewInstaller).to receive_messages(preinstall: true, install: true)
      allow(Homebrew::Bundle::MacAppStoreInstaller).to receive_messages(preinstall: true, install: true)
      allow(Homebrew::Bundle::VscodeExtensionInstaller).to receive_messages(preinstall: true, install: true)
      allow_any_instance_of(Pathname).to receive(:read).and_return(brewfile_contents)

      expect(Homebrew::Bundle).not_to receive(:system)
      expect { described_class.run }.to raise_error(SystemExit)
    end
  end
end
