# frozen_string_literal: true

require "spec_helper"
require "extend/kernel"

describe Bundle::VscodeExtensionInstaller do
  context "when VSCode is not installed" do
    before do
      described_class.reset!
      allow(Bundle).to receive_messages(vscode_installed?: false, cask_installed?: true)
    end

    it "tries to install vscode" do
      expect(Bundle).to \
        receive(:system).with(HOMEBREW_BREW_FILE, "install", "--cask", "visual-studio-code", verbose: false)
                        .and_return(true)
      expect { described_class.preinstall("foo") }.to raise_error(RuntimeError)
    end
  end

  context "when VSCode is installed" do
    before do
      allow(Bundle).to receive(:vscode_installed?).and_return(true)
    end

    context "when extension is installed" do
      before do
        allow(described_class).to receive(:installed_extensions).and_return(["foo"])
      end

      it "skips" do
        expect(Bundle).not_to receive(:system)
        expect(described_class.preinstall("foo")).to be(false)
      end

      it "skips ignoring case" do
        expect(Bundle).not_to receive(:system)
        expect(described_class.preinstall("Foo")).to be(false)
      end
    end

    context "when extension is not installed" do
      before do
        allow(described_class).to receive(:installed_extensions).and_return([])
      end

      it "installs extension" do
        expect(Bundle).to receive(:system).with("code", "--install-extension", "foo", verbose: false).and_return(true)
        expect(described_class.preinstall("foo")).to be(true)
        expect(described_class.install("foo")).to be(true)
      end

      it "installs extension when euid != uid and Process::UID.re_exchangeable? returns true" do
        expect(Process).to receive(:euid).and_return(1).once
        expect(Process::UID).to receive(:re_exchangeable?).and_return(true).once
        expect(Process::UID).to receive(:re_exchange).twice

        expect(Bundle).to receive(:system).with("code", "--install-extension", "foo", verbose: false).and_return(true)
        expect(described_class.preinstall("foo")).to be(true)
        expect(described_class.install("foo")).to be(true)
      end

      it "installs extension when euid != uid and Process::UID.re_exchangeable? returns false" do
        expect(Process).to receive(:euid).and_return(1).once
        expect(Process::UID).to receive(:re_exchangeable?).and_return(false).once
        expect(Process::Sys).to receive(:seteuid).twice

        expect(Bundle).to receive(:system).with("code", "--install-extension", "foo", verbose: false).and_return(true)
        expect(described_class.preinstall("foo")).to be(true)
        expect(described_class.install("foo")).to be(true)
      end
    end
  end
end
