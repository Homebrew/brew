# typed: true
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
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      specify do
        expect(dumper.extensions).to be_empty
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

        allow(Utils).to receive(:popen_read_text)
          .with(Pathname("code"), "--list-extensions", err: File::NULL)
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

        allow(Utils).to receive(:popen_read_text)
          .with(Pathname("code"), "--list-extensions", err: File::NULL)
          .and_return(output)

        expect(dumper.extensions).to eql(["github.codespaces"])
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

        it "installs multiple extensions in one native batch" do
          entries = [
            Homebrew::Bundle::Dsl::Entry.new(:vscode, "example.foo"),
            Homebrew::Bundle::Dsl::Entry.new(:vscode, "example.bar"),
          ]
          expect(described_class.batch_installable?("example.foo")).to be(true)
          expect(Homebrew::Bundle).to receive(:system)
            .with(Pathname("code"), "--install-extension", "example.foo",
                  "--install-extension", "example.bar", verbose: false)
            .and_return(true)

          expect(described_class.install_batch!(entries, verbose: false)).to be(true)
        end
      end
    end
  end
end
