# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/krew"
require "bundle/extensions/npm"
require "bundle/extensions/winget"
require "bundle/shared_examples/inventory"

RSpec.describe Homebrew::Bundle::Krew do
  let(:inventory_output) { "example-tool\n" }
  let(:inventory_records) { ["example-tool"] }

  describe "inventory" do
    include_examples "a checked package inventory"

    test_each([
      " ",
      "\t",
      " example-tool",
      "example-tool ",
      "example-tool other-tool",
      "example-tool\tother-tool",
      "example-tool\rother-tool",
      "\v",
      "\f",
      "\u00a0",
      "\u2003",
    ]) do |name|
      it "rejects a plugin name containing whitespace: #{name.dump}" do
        write_inventory(output: "#{name}\n")

        expect { described_class.packages }
          .to raise_error(RuntimeError, "Invalid Krew inventory: plugin names cannot contain whitespace")
      end
    end

    test_each([:packages, :installed_packages]) do |inventory_method|
      it "retries malformed #{inventory_method} without reset" do
        write_inventory(output: "example-tool\n \n")
        expect { described_class.public_send(inventory_method) }
          .to raise_error(RuntimeError, "Invalid Krew inventory: plugin names cannot contain whitespace")
        write_inventory(output: inventory_output)

        expect(described_class.public_send(inventory_method)).to eq(inventory_records)
      end
    end

    it "preserves an existing Brewfile when a successful command returns malformed inventory" do
      brewfile = mktmpdir/"Brewfile"
      brewfile.write "# original\n"
      write_inventory(output: "example-tool\n \n")

      expect do
        Homebrew::Bundle::Dumper.dump_brewfile(
          global: false, file: brewfile.to_s, describe: false, force: true, no_restart: false,
          formulae: false, taps: false, casks: false, extension_types: { krew: true }
        )
      end.to raise_error(RuntimeError, "Invalid Krew inventory: plugin names cannot contain whitespace")
      expect(brewfile.read).to eq("# original\n")
    end
  end

  it_behaves_like "a checked inventory", :installed_packages

  describe "selected extension snapshots" do
    let(:krew) { mktmpdir/"krew" }
    let(:npm) { mktmpdir/"npm" }
    let(:brewfile) { mktmpdir/"Brewfile" }

    before do
      described_class.reset!
      Homebrew::Bundle::Npm.reset!
      krew.write "#!/bin/sh\nprintf '%s\\n' 'example-tool'\nexit 2\n"
      krew.chmod 0755
      npm.write "#!/bin/sh\nprintf '%s' '{\"dependencies\":{\"example-tool\":{}}}'\n"
      npm.chmod 0755
      allow(described_class).to receive(:package_manager_executable).and_return(krew)
      allow(Homebrew::Bundle::Npm).to receive(:package_manager_executable).and_return(npm)
      allow(Homebrew::Bundle).to receive(:dump_package_types).and_return([
        Homebrew::Bundle::Npm, described_class, Homebrew::Bundle::Winget
      ])
    end

    after do
      described_class.reset!
      Homebrew::Bundle::Npm.reset!
    end

    it "preserves the destination when a later selected extension fails" do
      brewfile.write "# original\n"
      expect do
        Homebrew::Bundle::Dumper.dump_brewfile(
          global: false, file: brewfile.to_s, describe: false, force: true, no_restart: false,
          formulae: false, taps: false, casks: false, extension_types: { npm: true, krew: true }
        )
      end.to raise_error(ErrorDuringExecution)
      expect(brewfile.read).to eq("# original\n")
    end

    it "does not query unselected managers or require PowerShell" do
      expect(Homebrew::Bundle::Winget).not_to receive(:package_manager_executable)
      expect(described_class).not_to receive(:package_manager_executable)
      Homebrew::Bundle::Dumper.dump_brewfile(
        global: false, file: brewfile.to_s, describe: false, force: true, no_restart: false,
        formulae: false, taps: false, casks: false, extension_types: { npm: true, krew: false, winget: false }
      )
      expect(brewfile.read).to eq("npm \"example-tool\"\n")
    end
  end

  describe "dumping" do
    subject(:dumper) { described_class }

    context "when krew is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_installed?).and_return(false)
      end

      it "returns an empty list and dumps an empty string" do
        expect(dumper.packages).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "when krew is installed" do
      before do
        described_class.reset!
        allow(described_class).to receive_messages(package_manager_installed?: true,
                                                   package_manager_executable: Pathname.new("kubectl-krew"))
      end

      it "preserves plugin order and custom indexes while removing duplicates and line endings" do
        allow(described_class).to receive(:command_output)
          .with(Pathname("kubectl-krew"), args: ["list"])
          .and_return("other-tool\r\ncustom/example-tool\nother-tool\nexample-tool\n")

        expect(dumper.packages).to eql(%w[other-tool custom/example-tool example-tool])
      end

      it "handles the blank line emitted when no plugins are installed" do
        allow(described_class).to receive(:command_output).with(Pathname("kubectl-krew"),
                                                                args: ["list"]).and_return("\n")

        expect(dumper.packages).to be_empty
      end

      it "dumps plugin list" do
        allow(dumper).to receive(:packages).and_return(["example-tool", "third-tool", "other-tool"])
        expect(dumper.dump).to eql("krew \"example-tool\"\nkrew \"third-tool\"\nkrew \"other-tool\"")
      end
    end
  end

  describe "bootstrap cache invalidation" do
    let(:bootstrap_executable) { Pathname("kubectl-krew") }

    before do
      allow(described_class).to receive(:command_output).with(bootstrap_executable, args: ["list"])
                                                        .and_return("example-tool\n")
    end

    it_behaves_like "an inventory refreshed after bootstrap", "example-tool"
  end

  describe "installing" do
    context "when kubectl-krew is not found" do
      before do
        described_class.reset!
        allow(described_class).to receive_messages(package_manager_executable: nil,
                                                   package_manager_installed?: false)
      end

      it "tries to install krew" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "krew", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("example-tool") }.to raise_error(RuntimeError)
      end

      it "preserves upgrade_formulae while bootstrapping krew" do
        Homebrew::Bundle.upgrade_formulae = "foo,bar"

        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "krew", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("example-tool") }.to raise_error(RuntimeError)
        expect(Homebrew::Bundle.upgrade_formulae).to eql(["foo", "bar"])
      end
    end

    context "when kubectl-krew is installed" do
      before do
        allow(described_class).to receive_messages(
          package_manager_executable: Pathname.new("/usr/local/bin/kubectl-krew"),
          package_manager_installed?: true,
        )
      end

      context "when plugin is installed" do
        before do
          allow(described_class).to receive(:installed_packages).and_return(["example-tool"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("example-tool")).to be(false)
        end
      end

      context "when plugin is not installed" do
        before do
          described_class.reset!
          allow(described_class).to receive_messages(
            package_manager_executable: Pathname.new("/usr/local/bin/kubectl-krew"),
            package_manager_installed?: true,
            installed_packages:         [],
            packages:                   [],
          )
        end

        it "installs plugin" do
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            expect(ENV.fetch("PATH", "")).to start_with("/usr/local/bin:")
            expect(args).to eq(["/usr/local/bin/kubectl-krew", "install", "example-tool"])
            expect(verbose).to be(false)
            true
          end
          expect(described_class.preinstall!("example-tool")).to be(true)
          expect(described_class.install!("example-tool")).to be(true)
        end

        it "updates dump output after install" do
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            expect(args).to eq(["/usr/local/bin/kubectl-krew", "install", "example-tool"])
            expect(verbose).to be(false)
            true
          end

          described_class.install!("example-tool")

          expect(described_class.dump).to eql('krew "example-tool"')
        end
      end
    end
  end

  describe "cleanup" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(
        package_manager_executable: Pathname.new("/usr/local/bin/kubectl-krew"),
        package_manager_installed?: true,
        packages:                   %w[example-tool third-tool other-tool],
        installed_packages:         %w[example-tool third-tool other-tool],
      )
    end

    it "returns plugins not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:krew, "example-tool")]
      expect(described_class.cleanup_items(entries)).to eql(%w[third-tool other-tool])
    end

    it "returns the uninstall command result" do
      allow(Homebrew::Bundle).to receive(:system).with("/usr/local/bin/kubectl-krew", "uninstall", "example",
                                                       verbose: false)
                                                 .and_return(false)

      expect(
        described_class.uninstall_package!("example", executable: Pathname("/usr/local/bin/kubectl-krew")),
      ).to be(false)
    end

    it "uninstalls plugins" do
      expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
        expect(ENV.fetch("PATH", "")).to start_with("/usr/local/bin:")
        expect(args).to eq(["/usr/local/bin/kubectl-krew", "uninstall", "third-tool"])
        expect(verbose).to be(false)
        true
      end

      expect { described_class.cleanup!(["third-tool"]) }.to output("Uninstalled 1 krew plugin\n").to_stdout
    end
  end
end
