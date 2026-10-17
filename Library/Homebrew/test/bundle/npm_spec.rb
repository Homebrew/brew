# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/npm"
require "bundle/installer"
require "language/node"

RSpec.describe Homebrew::Bundle::Npm do
  describe "dumping" do
    subject(:dumper) { described_class }

    context "when npm is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      specify do
        expect(dumper.packages).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "when npm is installed" do
      let(:npm_list_args) { [Pathname("npm"), "list", "-g", "--depth=0", "--json"] }

      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("npm"))
      end

      it "returns package list" do
        allow(Utils).to receive(:popen_read_text).with(*npm_list_args, err: File::NULL).and_return(<<~JSON)
          {
            "dependencies": {
              "npm": { "version": "11.11.0" },
              "vercel": { "version": "39.0.0" },
              "typescript": { "version": "5.7.3" }
            }
          }
        JSON

        expect(dumper.packages).to eql(%w[vercel typescript])
      end

      it "adds npm's directory to PATH when listing packages" do
        npm = mktmpdir/"bin/npm"
        npm.dirname.mkpath
        npm.write("")

        allow(described_class).to receive(:package_manager_executable).and_return(npm)
        expect(Utils).to receive(:popen_read_text)
          .with(npm, "list", "-g", "--depth=0", "--json", err: File::NULL) do
          expect(ENV.fetch("PATH", "")).to start_with("#{npm.dirname}:")
          '{"dependencies":{"eslint":{"version":"10.4.0"}}}'
        end

        expect(dumper.packages).to eql(["eslint"])
      end

      it "excludes npm itself from the package list" do
        allow(Utils).to receive(:popen_read_text).with(*npm_list_args, err: File::NULL).and_return(<<~JSON)
          {
            "dependencies": {
              "npm": { "version": "11.11.0" }
            }
          }
        JSON

        expect(dumper.packages).to be_empty
      end

      it "handles invalid JSON" do
        allow(Utils).to receive(:popen_read_text).with(*npm_list_args, err: File::NULL).and_return("not json")

        expect(dumper.packages).to be_empty
      end

      it "handles empty output" do
        allow(Utils).to receive(:popen_read_text).with(*npm_list_args, err: File::NULL).and_return("")

        expect(dumper.packages).to be_empty
      end

      it "dumps package list" do
        allow(dumper).to receive(:packages).and_return(["vercel", "typescript"])
        expect(dumper.dump).to eql("npm \"vercel\"\nnpm \"typescript\"")
      end
    end
  end

  describe "outdated packages" do
    before do
      described_class.reset!
      allow(described_class).to receive(:package_manager_executable).and_return(Pathname("npm"))
    end

    it "lists outdated packages, including scoped packages, but excludes npm" do
      allow(Utils).to receive(:popen_read_text)
        .with(Pathname("npm"), "outdated", "-g", "--depth=0", "--json", err: File::NULL).and_return(<<~JSON)
          {
            "npm": { "current": "11.10.0", "latest": "11.11.0" },
            "vercel": { "current": "38.0.0", "latest": "39.0.0" },
            "@example/cli": { "current": "1.0.0", "latest": "2.0.0" }
          }
        JSON

      expect(described_class.outdated_packages).to eq(["vercel", "@example/cli"])
    end

    it "adds npm's directory to PATH when checking outdated packages" do
      allow(Utils).to receive(:popen_read_text) do
        expect(ENV.fetch("PATH")).to start_with(".:#{ORIGINAL_PATHS.join(":")}")
        "{}"
      end

      described_class.outdated_packages
    end

    it "caches outdated packages until reset" do
      expect(Utils).to receive(:popen_read_text).twice.and_return("{}")

      described_class.outdated_packages
      described_class.outdated_packages
      described_class.reset!
      described_class.outdated_packages
    end

    it "handles empty or invalid output" do
      expect(["", "not json", "{}"].map do |output|
        described_class.reset!
        allow(Utils).to receive(:popen_read_text).and_return(output)

        described_class.outdated_packages
      end).to eq([[], [], []])
    end

    it "returns no outdated packages when npm is not installed" do
      allow(described_class).to receive(:package_manager_executable).and_return(nil)

      expect(described_class.outdated_packages).to be_empty
    end
  end

  describe "checking" do
    let(:entries) { [Homebrew::Bundle::Dsl::Entry.new(:npm, "vercel")] }

    before do
      described_class.reset!
      allow(described_class).to receive_messages(installed_packages: ["vercel"], outdated_packages: ["vercel"])
    end

    it "reports installed packages that need upgrading" do
      expect(described_class.check(entries)).to eq(["npm Package vercel needs to be upgraded."])
    end

    it "reports outdated packages when exiting on the first error" do
      expect(described_class.check(entries, exit_on_first_error: true))
        .to eq(["npm Package vercel needs to be upgraded."])
    end

    it "accepts up-to-date packages" do
      allow(described_class).to receive(:outdated_packages).and_return([])

      expect(described_class.check(entries)).to be_empty
    end

    it "skips checking outdated packages with no_upgrade" do
      expect(described_class).not_to receive(:outdated_packages)

      expect(described_class.check(entries, no_upgrade: true)).to be_empty
    end

    it "reports missing packages without checking outdated packages" do
      allow(described_class).to receive(:installed_packages).and_return([])
      expect(described_class).not_to receive(:outdated_packages)

      expect(described_class.check(entries)).to eq(["npm Package vercel needs to be installed."])
    end

    it "does not check outdated packages without npm entries" do
      expect(described_class).not_to receive(:outdated_packages)

      described_class.check([])
    end
  end

  describe "cleanup" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(
        package_manager_executable: Pathname.new("/opt/homebrew/bin/npm"),
        packages:                   %w[vercel typescript prettier],
        installed_packages:         %w[vercel typescript prettier],
      )
    end

    it "returns packages not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:npm, "vercel")]
      expect(described_class.cleanup_items(entries)).to eql(%w[typescript prettier])
    end

    it "returns empty when all packages are in Brewfile" do
      entries = [
        Homebrew::Bundle::Dsl::Entry.new(:npm, "vercel"),
        Homebrew::Bundle::Dsl::Entry.new(:npm, "typescript"),
        Homebrew::Bundle::Dsl::Entry.new(:npm, "prettier"),
      ]
      expect(described_class.cleanup_items(entries)).to eql([])
    end

    it "returns frozen empty array when npm is not installed" do
      allow(described_class).to receive(:package_manager_installed?).and_return(false)
      entries = [Homebrew::Bundle::Dsl::Entry.new(:npm, "vercel")]
      expect(described_class.cleanup_items(entries)).to eql([])
    end
  end

  describe ".cleanup! inherited from Extension" do
    before do
      Homebrew.failed = false
      allow(described_class).to receive(:package_manager_executable)
        .and_return(Pathname("/usr/bin/false"))
    end

    it "reports a failed uninstall command" do
      expect do
        described_class.cleanup!(["example"])
      end.to(
        change(Homebrew, :failed?).from(false).to(true)
          .and(output(/Uninstalled 0 npm packages/).to_stdout)
          .and(output(/Failed to uninstall npm packages: example/).to_stderr),
      )
    end

    it "reports successful cleanup" do
      allow(Homebrew::Bundle).to receive(:system).and_return(true)

      expect { described_class.cleanup!(["example"]) }.to output(/Uninstalled 1 npm package/).to_stdout
    end

    it "counts successful commands and continues after failure" do
      { "first" => true, "second" => false, "third" => true }.each do |name, success|
        expect(Homebrew::Bundle).to receive(:system)
          .with("/usr/bin/false", "uninstall", "-g", name, verbose: false).ordered.and_return(success)
      end

      expect do
        described_class.cleanup!(%w[first second third])
      end.to(
        change(Homebrew, :failed?).from(false).to(true)
          .and(output(/Uninstalled 2 npm packages/).to_stdout)
          .and(output(/Failed to uninstall npm packages: second/).to_stderr),
      )
    end

    it "does not clear an earlier failure after successful uninstalls" do
      Homebrew.failed = true
      allow(Homebrew::Bundle).to receive(:system).and_return(true)
      allow(described_class).to receive(:puts)

      expect { described_class.cleanup!(["example"]) }.not_to change(Homebrew, :failed?)
    end
  end

  describe "installing" do
    context "when npm is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "tries to install node" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "node", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("vercel") }.to raise_error(RuntimeError)
      end
    end

    context "when npm is installed" do
      before do
        described_class.reset!
        allow(described_class).to receive_messages(package_manager_executable: Pathname.new("npm"),
                                                   outdated_packages:          [])
      end

      context "when package is installed" do
        before do
          allow(described_class).to receive(:installed_packages)
            .and_return(["vercel"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("vercel")).to be(false)
        end

        context "when package is outdated" do
          before do
            allow(described_class).to receive(:outdated_packages).and_return(["vercel"])
          end

          it "needs upgrading" do
            expect(described_class.preinstall!("vercel")).to be(true)
          end

          it "uses the upgrade verb" do
            expect(described_class.install_verb("vercel")).to eq("Upgrading")
          end

          it "skips checking outdated packages with no_upgrade" do
            expect(described_class).not_to receive(:outdated_packages)

            expect(described_class.preinstall!("vercel", no_upgrade: true)).to be(false)
          end

          it "upgrades using npm install" do
            expect(Homebrew::Bundle).to receive(:system)
              .with("npm", "install", *Language::Node.npm_install_security_args, "-g", "vercel", verbose: true)
              .and_return(true)

            expect { described_class.install!("vercel", verbose: true) }
              .to output("Upgrading vercel npm package. It is installed but not up-to-date.\n").to_stdout
          end

          it "batches upgrades and new installs with the appropriate messages" do
            entries = [
              Homebrew::Bundle::Dsl::Entry.new(:npm, "vercel"),
              Homebrew::Bundle::Dsl::Entry.new(:npm, "typescript"),
            ]
            expect(Homebrew::Bundle).to receive(:system)
              .with("npm", "install", *Language::Node.npm_install_security_args,
                    "-g", "vercel", "typescript", verbose: false).and_return(true)

            expect { Homebrew::Bundle::Installer.install!(entries, quiet: true) }
              .to output("Upgrading vercel\nInstalling typescript\n").to_stdout
          end
        end
      end

      context "when package is not installed" do
        before do
          allow(described_class).to receive_messages(
            package_manager_executable: Pathname.new("/opt/homebrew/bin/npm"),
            installed_packages:         [],
          )
        end

        it "installs package" do
          expect(Homebrew::Bundle).to receive(:system)
            .with(
              "/opt/homebrew/bin/npm",
              "install",
              "--min-release-age=1",
              "--cache=#{HOMEBREW_CACHE}/npm_cache",
              "--ignore-scripts",
              "-g",
              "vercel",
              verbose: false,
            )
            .and_return(true)
          expect(described_class.preinstall!("vercel")).to be(true)
          expect(described_class.install!("vercel")).to be(true)
        end

        it "installs multiple packages in npm's native batch" do
          entries = [
            Homebrew::Bundle::Dsl::Entry.new(:npm, "vercel"),
            Homebrew::Bundle::Dsl::Entry.new(:npm, "typescript"),
          ]
          expect(described_class.batch_installable?("vercel")).to be(true)
          expect(Homebrew::Bundle).to receive(:system)
            .with(
              "/opt/homebrew/bin/npm",
              "install",
              "--min-release-age=1",
              "--cache=#{HOMEBREW_CACHE}/npm_cache",
              "--ignore-scripts",
              "-g",
              "vercel",
              "typescript",
              verbose: false,
            )
            .and_return(true)

          expect(described_class.install_batch!(entries, verbose: false)).to be(true)
        end
      end
    end
  end
end
