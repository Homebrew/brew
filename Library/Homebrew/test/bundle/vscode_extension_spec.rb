# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/vscode_extension"
require "extend/kernel"

RSpec.describe Homebrew::Bundle::VscodeExtension do
  describe "dumping" do
    subject(:dumper) { described_class }

    context "when vscode is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive_messages(package_manager_executable: nil, "`": "")
      end

      it "returns an empty list" do
        expect(dumper.extensions).to be_empty
      end

      it "dumps an empty string" do # rubocop:todo RSpec/AggregateExamples
        expect(dumper.dump).to eql("")
      end
    end

    context "when vscode is installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("code"))
      end

      it "returns package list" do
        output = <<~EOF
          catppuccin.catppuccin-vsc
          davidanson.vscode-markdownlint
          streetsidesoftware.code-spell-checker
          tamasfe.even-better-toml
        EOF

        allow(described_class).to receive(:`)
          .with('"code" --list-extensions 2>/dev/null')
          .and_return(output)
        expect(dumper.extensions).to eql([
          "catppuccin.catppuccin-vsc",
          "davidanson.vscode-markdownlint",
          "streetsidesoftware.code-spell-checker",
          "tamasfe.even-better-toml",
        ])
      end
    end
  end

  describe "installing" do
    context "when VSCode is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
        allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
      end

      it "tries to install vscode" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--cask", "visual-studio-code", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("foo") }.to raise_error(RuntimeError)
      end
    end

    context "when VSCode is installed" do
      before do
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname("code"))
      end

      context "when extension is installed" do
        before do
          allow(described_class).to receive(:installed_extensions).and_return(["foo"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("foo")).to be(false)
        end

        it "skips ignoring case" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("Foo")).to be(false)
        end
      end

      context "when extension is not installed" do
        before do
          allow(described_class).to receive(:installed_extensions).and_return([])
        end

        it "installs extension" do
          expect(Homebrew::Bundle).to \
            receive(:system).with(Pathname("code"), "--install-extension", "foo", verbose: false).and_return(true)
          expect(described_class.preinstall!("foo")).to be(true)
          expect(described_class.install!("foo")).to be(true)
        end

        it "installs extension when euid != uid and Process::UID.re_exchangeable? returns true" do
          allow(Process).to receive(:uid).and_return(0)
          allow(Etc).to receive(:getpwuid).with(0).and_return(double(dir: "/root"))
          expect(Process).to receive(:euid).and_return(1).once
          expect(Process::UID).to receive(:re_exchangeable?).and_return(true).once
          expect(Process::UID).to receive(:re_exchange).twice

          expect(Homebrew::Bundle).to \
            receive(:system).with(Pathname("code"), "--install-extension", "foo", verbose: false).and_return(true)
          expect(described_class.preinstall!("foo")).to be(true)
          expect(described_class.install!("foo")).to be(true)
        end

        it "installs extension when euid != uid and Process::UID.re_exchangeable? returns false" do
          allow(Process).to receive(:uid).and_return(0)
          allow(Etc).to receive(:getpwuid).with(0).and_return(double(dir: "/root"))
          expect(Process).to receive(:euid).and_return(1).once
          expect(Process::UID).to receive(:re_exchangeable?).and_return(false).once
          expect(Process::Sys).to receive(:seteuid).twice

          expect(Homebrew::Bundle).to \
            receive(:system).with(Pathname("code"), "--install-extension", "foo", verbose: false).and_return(true)
          expect(described_class.preinstall!("foo")).to be(true)
          expect(described_class.install!("foo")).to be(true)
        end
      end
    end
  end
end
