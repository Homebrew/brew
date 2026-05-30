# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/vscode_extension"
require "extend/kernel"

RSpec.describe Homebrew::Bundle::VscodeExtension do
  let(:klass) { Homebrew::Bundle::VscodeExtension }

  describe "dumping" do
    subject(:dumper) { klass }

    context "when vscode is not installed" do
      before do
        klass.reset!
        allow(klass).to receive_messages(package_manager_executable: nil, "`": "")
      end

      specify do
        expect(dumper.extensions).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "when vscode is installed" do
      before do
        klass.reset!
        allow(klass).to receive(:package_manager_executable).and_return(Pathname.new("code"))
      end

      it "returns package list" do
        output = <<~EOF
          catppuccin.catppuccin-vsc
          davidanson.vscode-markdownlint
          streetsidesoftware.code-spell-checker
          tamasfe.even-better-toml
        EOF

        allow(klass).to receive(:`)
          .with('"code" --list-extensions 2>/dev/null')
          .and_return(output)
        expect(dumper.extensions).to eql([
          "catppuccin.catppuccin-vsc",
          "davidanson.vscode-markdownlint",
          "streetsidesoftware.code-spell-checker",
          "tamasfe.even-better-toml",
        ])
      end

      it "ignores VSCode server setup output" do
        output = <<~EOF
          updating vs code server to version f6cfa2ea2403534de03f069bdf160d06451ed282
          downloading:     \b\b\b\b  0%\b\b\b\b100%
          unpacked 3485 files and folders to /home/mike/.vscode-server/bin/f6cfa2ea2403534de03f069bdf160d06451ed282.
          GitHub.codespaces
        EOF

        allow(klass).to receive(:`)
          .with('"code" --list-extensions 2>/dev/null')
          .and_return(output)

        expect(dumper.extensions).to eql(["github.codespaces"])
      end
    end
  end

  describe "installing" do
    context "when VSCode is not installed" do
      before do
        klass.reset!
        allow(klass).to receive(:package_manager_executable).and_return(nil)
        allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
      end

      it "tries to install vscode" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--cask", "visual-studio-code", verbose: false)
                          .and_return(true)
        expect { klass.preinstall!("foo") }.to raise_error(RuntimeError)
      end
    end

    context "when VSCode is installed" do
      before do
        allow(klass).to receive(:package_manager_executable).and_return(Pathname("code"))
      end

      context "when extension is installed" do
        before do
          allow(klass).to receive(:installed_extensions).and_return(["foo"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(klass.preinstall!("foo")).to be(false)
        end

        it "skips ignoring case" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(klass.preinstall!("Foo")).to be(false)
        end
      end

      context "when extension is not installed" do
        before do
          allow(klass).to receive(:installed_extensions).and_return([])
        end

        it "installs extension" do
          expect(Homebrew::Bundle).to \
            receive(:system).with(Pathname("code"), "--install-extension", "foo", verbose: false).and_return(true)
          expect(klass.preinstall!("foo")).to be(true)
          expect(klass.install!("foo")).to be(true)
        end

        it "installs extension when euid != uid and Process::UID.re_exchangeable? returns true" do
          allow(Process).to receive(:uid).and_return(0)
          allow(Etc).to receive(:getpwuid).with(0).and_return(double(dir: "/root"))
          expect(Process).to receive(:euid).and_return(1).once
          expect(Process::UID).to receive(:re_exchangeable?).and_return(true).once
          expect(Process::UID).to receive(:re_exchange).twice

          expect(Homebrew::Bundle).to \
            receive(:system).with(Pathname("code"), "--install-extension", "foo", verbose: false).and_return(true)
          expect(klass.preinstall!("foo")).to be(true)
          expect(klass.install!("foo")).to be(true)
        end

        it "installs extension when euid != uid and Process::UID.re_exchangeable? returns false" do
          allow(Process).to receive(:uid).and_return(0)
          allow(Etc).to receive(:getpwuid).with(0).and_return(double(dir: "/root"))
          expect(Process).to receive(:euid).and_return(1).once
          expect(Process::UID).to receive(:re_exchangeable?).and_return(false).once
          expect(Process::Sys).to receive(:seteuid).twice

          expect(Homebrew::Bundle).to \
            receive(:system).with(Pathname("code"), "--install-extension", "foo", verbose: false).and_return(true)
          expect(klass.preinstall!("foo")).to be(true)
          expect(klass.install!("foo")).to be(true)
        end
      end
    end
  end
end
