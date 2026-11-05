# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/installer"
require "bundle/shared_examples/inventory"
require "bundle/extensions/vscode_extension"
require "extend/kernel"

RSpec.describe Homebrew::Bundle::VscodeExtension do
  let(:inventory_output) { "example.extension\n" }
  let(:inventory_records) { ["example.extension"] }

  it_behaves_like "a checked package inventory"
  it_behaves_like "a checked inventory", :installed_packages

  describe "upgrades" do
    before do
      allow(described_class).to receive_messages(package_manager_executable: Pathname("code"),
                                                 installed_extensions:       ["example.extension"])
    end

    test_each([false, true]) do |exit_on_first_error|
      it "accepts an installed extension with exit_on_first_error=#{exit_on_first_error}" do
        expect(described_class.check([Homebrew::Bundle::Dsl::Entry.new(:vscode, "example.extension")],
                                     exit_on_first_error:))
          .to be_empty
      end
    end

    it "accepts an extension immediately after installation" do
      allow(described_class).to receive(:installed_extensions).and_return([])
      allow(Homebrew::Bundle).to receive(:system).and_return(true)
      described_class.install!("example.extension")

      expect(described_class.check([Homebrew::Bundle::Dsl::Entry.new(:vscode, "example.extension")]))
        .to be_empty
    end

    it "does not run the editor during the read-only check" do
      expect(Homebrew::Bundle).not_to receive(:system)
      described_class.check([Homebrew::Bundle::Dsl::Entry.new(:vscode, "example.extension")])
    end

    it "accepts an installed extension with no_upgrade" do
      expect(described_class.check([Homebrew::Bundle::Dsl::Entry.new(:vscode, "example.extension")],
                                   no_upgrade: true))
        .to be_empty
    end

    it "schedules native upgrade checks for installed extensions" do
      expect(described_class.preinstall!("example.extension")).to be(true)
    end

    it "skips installed extensions with no_upgrade" do
      expect(described_class.preinstall!("example.extension", no_upgrade: true)).to be(false)
    end

    it "asks the editor to upgrade only the requested extension" do
      expect(Homebrew::Bundle).to receive(:system)
        .with(Pathname("code"), "--install-extension", "example.extension", "--force", verbose: false)
        .and_return(true)
      described_class.install!("example.extension")
    end

    it "upgrades only the requested extensions in a native batch" do
      expect(Homebrew::Bundle).to receive(:system)
        .with(Pathname("code"), "--install-extension", "example.extension", "--force", verbose: false)
        .and_return(true)
      described_class.install_batch!([Homebrew::Bundle::Dsl::Entry.new(:vscode, "example.extension")])
    end

    it "labels upgrades and new installs in a native batch" do
      allow(Homebrew::Bundle).to receive(:system).and_return(true)
      expect do
        Homebrew::Bundle::Installer.install!([
          described_class.entry("example.extension"), described_class.entry("example.new")
        ], quiet: true)
      end.to output("Upgrading example.extension\nInstalling example.new\n").to_stdout
    end

    it "describes an installed extension as upgrading in verbose output" do
      allow(Homebrew::Bundle).to receive(:system).and_return(true)
      expect { described_class.install!("example.extension", verbose: true) }
        .to output("Upgrading example.extension VSCode extension.\n").to_stdout
    end
  end

  describe "cleanup" do
    test_each([false, nil]) do |result|
      it "reports #{result.inspect} and continues cleanup" do
        Homebrew.failed = false
        ENV["PATH"] = "/usr/bin:/bin"
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname("code"))
        expect(Kernel).to receive(:system)
          .with("code", "--uninstall-extension", "publisher.first").ordered do
            expect(ENV.fetch("PATH")).to eq("/usr/bin:/bin")
            result
          end
        expect(Kernel).to receive(:system)
          .with("code", "--uninstall-extension", "publisher.second")
          .ordered.and_return(true)

        expect do
          described_class.cleanup!(%w[publisher.first publisher.second])
        end.to(
          change(Homebrew, :failed?).from(false).to(true)
            .and(output(a_string_including("publisher.first")).to_stderr)
            .and(output("Uninstalled 1 vscode extension\n").to_stdout),
        )
      end
    end
  end

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
          example.first-extension
          example.second-extension
          other.first-extension
          other.second-extension
        EOF

        allow(described_class).to receive(:command_output)
          .with(Pathname("code"), args: ["--list-extensions"])
          .and_return(output)
        expect(dumper.extensions).to eql([
          "example.first-extension",
          "example.second-extension",
          "other.first-extension",
          "other.second-extension",
        ])
      end

      it "ignores VSCode server setup output" do
        output = <<~EOF
          updating vs code server to version f6cfa2ea2403534de03f069bdf160d06451ed282
          downloading:     \b\b\b\b  0%\b\b\b\b100%
          unpacked 3485 files and folders to /home/example/.vscode-server/bin/f6cfa2ea2403534de03f069bdf160d06451ed282.
          Example.Extension
        EOF

        allow(described_class).to receive(:command_output)
          .with(Pathname("code"), args: ["--list-extensions"])
          .and_return(output)

        expect(dumper.extensions).to eql(["example.extension"])
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
          expect(described_class.preinstall!("foo", no_upgrade: true)).to be(false)
        end

        it "skips ignoring case" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("Foo", no_upgrade: true)).to be(false)
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
