# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/shared_examples/inventory"
require "bundle/extensions/npm"
require "bundle/installer"
require "language/node"

RSpec.describe Homebrew::Bundle::Npm do
  let(:inventory_output) { '{"dependencies":{"example-tool":{}}}' }
  let(:inventory_records) { ["example-tool"] }

  it_behaves_like "a checked package inventory", empty_output: "{}"
  it_behaves_like "a checked inventory", :installed_packages, empty_output: "{}"

  describe "checked outdated inventory" do
    let(:inventory_output) { '{"example-tool":{"wanted":"1","latest":"2"}}' }

    it_behaves_like "a checked inventory", :outdated_packages, empty_output: "{}"
  end

  describe "checked JSON inventory" do
    let(:npm) { mktmpdir/"npm" }

    before do
      described_class.reset!
      allow(described_class).to receive(:package_manager_executable).and_return(npm)
    end

    after do
      described_class.reset!
    end

    def npm_result(json, status)
      npm.write "#!/bin/sh\nprintf '%s' #{JSON.generate(json).shellescape}\nexit #{status}\n"
      npm.chmod 0755
    end

    it "rejects a diagnostic envelope despite plausible dependencies" do
      npm_result({ "dependencies" => { "example-tool" => {} }, "error" => { "code" => "ENETWORK" } }, 1)
      expect { described_class.packages }.to raise_error(ErrorDuringExecution)
    end

    it "accepts installed packages from an ELSPROBLEMS tree and excludes missing packages" do
      npm_result({ "dependencies" => { "example-tool" => { "invalid" => true },
                                       "missing-tool" => { "missing" => true } },
                   "problems"     => ["missing: missing-tool from Example's tools"],
                   "error"        => { "code" => "ELSPROBLEMS" } }, 1)
      expect(described_class.packages).to eq(["example-tool"])
    end

    it "rejects invalid successful JSON" do
      npm_result([], 0)
      expect { described_class.packages }.to raise_error(RuntimeError, /Invalid npm list inventory/)
    end

    it "rejects failed empty outdated output" do
      npm.write "#!/bin/sh\nexit 1\n"
      npm.chmod 0755
      expect { described_class.outdated_packages }.to raise_error(ErrorDuringExecution)
    end

    test_each([{}, { "error" => { "code" => "ENETWORK" } },
               { "example-tool" => [] },
               { "example-tool" => [{ "wanted" => "1", "latest" => "2" }, {}] }]) do |json|
      it "rejects invalid nonzero outdated JSON #{json.inspect}" do
        npm_result(json, 1)
        expect { described_class.outdated_packages }.to raise_error(ErrorDuringExecution)
      end
    end

    it "accepts a real outdated package named error" do
      npm_result({ "error" => { "wanted" => "1", "latest" => "2" } }, 1)
      expect(described_class.outdated_packages).to eq(["error"])
    end

    it "accepts valid array-valued outdated records" do
      npm_result({ "example-tool" => [{ "current" => "1", "wanted" => "2", "latest" => "3" },
                                      { "current" => "2", "wanted" => "3", "latest" => "3" }] }, 1)
      expect(described_class.outdated_packages).to eq(["example-tool"])
    end
  end

  def stub_npm_list(output)
    allow(SystemCommand).to receive(:run)
      .with(Pathname("npm"), args: ["list", "-g", "--depth=0", "--json"], print_stderr: false)
      .and_return(stub_npm_output(output))
  end

  def stub_npm_output(output)
    SystemCommand::Result.new(["npm"], [[:stdout, output]],
                              instance_double(Process::Status, success?: true, exitstatus: 0),
                              secrets: [])
  end

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
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("npm"))
      end

      it "returns package list" do
        stub_npm_list(<<~JSON)
          {
            "dependencies": {
              "npm": { "version": "11.11.0" },
              "third-tool": { "version": "39.0.0" },
              "other-tool": { "version": "5.7.3" }
            }
          }
        JSON

        expect(dumper.packages).to eql(%w[third-tool other-tool])
      end

      it "adds npm's directory to PATH when listing packages" do
        npm = mktmpdir/"bin/npm"
        npm.dirname.mkpath
        npm.write("")

        allow(described_class).to receive(:package_manager_executable).and_return(npm)
        expect(SystemCommand).to receive(:run)
          .with(npm, args: ["list", "-g", "--depth=0", "--json"], print_stderr: false) do
          expect(ENV.fetch("PATH", "")).to start_with("#{npm.dirname}:")
          stub_npm_output('{"dependencies":{"third-tool":{"version":"10.4.0"}}}')
        end

        expect(dumper.packages).to eql(["third-tool"])
      end

      it "excludes npm itself from the package list" do
        stub_npm_list(<<~JSON)
          {
            "dependencies": {
              "npm": { "version": "11.11.0" }
            }
          }
        JSON

        expect(dumper.packages).to be_empty
      end

      it "handles invalid JSON" do
        stub_npm_list("not json")

        expect { dumper.packages }.to raise_error(/Invalid npm list inventory/)
      end

      it "handles empty output" do
        stub_npm_list("")

        expect { dumper.packages }.to raise_error(/Invalid npm list inventory/)
      end

      it "dumps package list" do
        allow(dumper).to receive(:packages).and_return(["third-tool", "other-tool"])
        expect(dumper.dump).to eql("npm \"third-tool\"\nnpm \"other-tool\"")
      end
    end
  end

  describe "outdated packages" do
    before do
      described_class.reset!
      allow(described_class).to receive(:package_manager_executable).and_return(Pathname("npm"))
    end

    it "lists outdated packages, including scoped packages, but excludes npm" do
      allow(SystemCommand).to receive(:run)
        .with(Pathname("npm"), args: ["outdated", "-g", "--depth=0", "--json"], print_stderr: false)
        .and_return(stub_npm_output(<<~JSON))
          {
            "npm": { "current": "11.10.0", "wanted": "11.11.0", "latest": "11.11.0" },
            "third-tool": { "current": "38.0.0", "wanted": "39.0.0", "latest": "39.0.0" },
            "@example/cli": { "current": "1.0.0", "wanted": "2.0.0", "latest": "2.0.0" }
          }
        JSON

      expect(described_class.outdated_packages).to eq(["third-tool", "@example/cli"])
    end

    it "adds npm's directory to PATH when checking outdated packages" do
      allow(SystemCommand).to receive(:run) do
        expect(ENV.fetch("PATH")).to start_with(".:#{ORIGINAL_PATHS.join(":")}")
        stub_npm_output("{}")
      end

      described_class.outdated_packages
    end

    test_each(["", "not json"]) do |output|
      it "rejects invalid outdated output #{output.inspect}" do
        allow(SystemCommand).to receive(:run).and_return(stub_npm_output(output))
        expect { described_class.outdated_packages }.to raise_error(/Invalid npm outdated inventory/)
      end
    end

    it "returns no outdated packages when npm is not installed" do
      allow(described_class).to receive(:package_manager_executable).and_return(nil)

      expect(described_class.outdated_packages).to be_empty
    end
  end

  describe "checking" do
    let(:entries) { [Homebrew::Bundle::Dsl::Entry.new(:npm, "third-tool")] }

    before do
      described_class.reset!
      allow(described_class).to receive_messages(installed_packages: ["third-tool"],
                                                 outdated_packages:  ["third-tool"])
    end

    it "reports installed packages that need upgrading" do
      expect(described_class.check(entries)).to eq(["npm Package third-tool needs to be upgraded."])
    end

    it "reports outdated packages when exiting on the first error" do
      expect(described_class.check(entries, exit_on_first_error: true))
        .to eq(["npm Package third-tool needs to be upgraded."])
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

      expect(described_class.check(entries)).to eq(["npm Package third-tool needs to be installed."])
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
        packages:                   %w[third-tool other-tool example-tool],
        installed_packages:         %w[third-tool other-tool example-tool],
      )
    end

    it "returns packages not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:npm, "third-tool")]
      expect(described_class.cleanup_items(entries)).to eql(%w[other-tool example-tool])
    end

    it "returns empty when all packages are in Brewfile" do
      entries = [
        Homebrew::Bundle::Dsl::Entry.new(:npm, "third-tool"),
        Homebrew::Bundle::Dsl::Entry.new(:npm, "other-tool"),
        Homebrew::Bundle::Dsl::Entry.new(:npm, "example-tool"),
      ]
      expect(described_class.cleanup_items(entries)).to eql([])
    end

    it "returns frozen empty array when npm is not installed" do
      allow(described_class).to receive(:package_manager_installed?).and_return(false)
      entries = [Homebrew::Bundle::Dsl::Entry.new(:npm, "third-tool")]
      expect(described_class.cleanup_items(entries)).to eql([])
    end
  end

  describe ".cleanup! inherited from Extension" do
    before do
      Homebrew.failed = false
      allow(described_class).to receive(:package_manager_executable)
        .and_return(Pathname("/usr/bin/false"))
    end

    it "reports a missing executable when removals are queued" do
      allow(described_class).to receive(:package_manager_executable).and_return(nil)

      expect do
        described_class.cleanup!(["example"])
      end.to(
        change(Homebrew, :failed?).from(false).to(true)
          .and(output(/Failed to uninstall npm packages: executable not found/).to_stderr),
      )
    end

    it "does not report a missing executable when no removals are queued" do
      allow(described_class).to receive(:package_manager_executable).and_return(nil)

      expect do
        described_class.cleanup!([])
      end.to(output("").to_stderr.and(output("").to_stdout))
    end

    it "reports a failed uninstall command" do
      expect do
        described_class.cleanup!(["example"])
      end.to(
        change(Homebrew, :failed?).from(false).to(true)
          .and(output(/^Uninstalled 0 npm packages$/).to_stdout)
          .and(output(/Failed to uninstall npm packages: example/).to_stderr),
      )
    end

    it "reports successful cleanup" do
      allow(Homebrew::Bundle).to receive(:system).and_return(true)

      expect do
        described_class.cleanup!(["example"])
      end.to output("Uninstalled 1 npm package\n").to_stdout.and output("").to_stderr
    end

    it "does not mark successful cleanup as failed" do
      allow(Homebrew::Bundle).to receive(:system).and_return(true)
      allow(described_class).to receive(:puts)

      expect { described_class.cleanup!(["example"]) }.not_to change(Homebrew, :failed?)
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
          .and(output("Uninstalled 2 npm packages\n").to_stdout)
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
        expect { described_class.preinstall!("third-tool") }.to raise_error(RuntimeError)
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
            .and_return(["third-tool"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("third-tool")).to be(false)
        end

        context "when package is outdated" do
          before do
            allow(described_class).to receive(:outdated_packages).and_return(["third-tool"])
          end

          it "needs upgrading" do
            expect(described_class.preinstall!("third-tool")).to be(true)
          end

          it "uses the upgrade verb" do
            expect(described_class.install_verb("third-tool")).to eq("Upgrading")
          end

          it "skips checking outdated packages with no_upgrade" do
            expect(described_class).not_to receive(:outdated_packages)

            expect(described_class.preinstall!("third-tool", no_upgrade: true)).to be(false)
          end

          it "upgrades using npm install" do
            expect(Homebrew::Bundle).to receive(:system)
              .with("npm", "install", *Language::Node.npm_install_security_args, "-g", "third-tool", verbose: true)
              .and_return(true)

            expect { described_class.install!("third-tool", verbose: true) }
              .to output("Upgrading third-tool npm package. It is installed but not up-to-date.\n").to_stdout
          end

          it "batches upgrades and new installs with the appropriate messages" do
            entries = [
              Homebrew::Bundle::Dsl::Entry.new(:npm, "third-tool"),
              Homebrew::Bundle::Dsl::Entry.new(:npm, "other-tool"),
            ]
            expect(Homebrew::Bundle).to receive(:system)
              .with("npm", "install", *Language::Node.npm_install_security_args,
                    "-g", "third-tool", "other-tool", verbose: false).and_return(true)

            expect { Homebrew::Bundle::Installer.install!(entries, quiet: true) }
              .to output("Upgrading third-tool\nInstalling other-tool\n").to_stdout
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
              "third-tool",
              verbose: false,
            )
            .and_return(true)
          expect(described_class.preinstall!("third-tool")).to be(true)
          expect(described_class.install!("third-tool")).to be(true)
        end

        it "installs multiple packages in npm's native batch" do
          entries = [
            Homebrew::Bundle::Dsl::Entry.new(:npm, "third-tool"),
            Homebrew::Bundle::Dsl::Entry.new(:npm, "other-tool"),
          ]
          expect(described_class.batch_installable?("third-tool")).to be(true)
          expect(Homebrew::Bundle).to receive(:system)
            .with(
              "/opt/homebrew/bin/npm",
              "install",
              "--min-release-age=1",
              "--cache=#{HOMEBREW_CACHE}/npm_cache",
              "--ignore-scripts",
              "-g",
              "third-tool",
              "other-tool",
              verbose: false,
            )
            .and_return(true)

          expect(described_class.install_batch!(entries, verbose: false)).to be(true)
        end
      end
    end
  end
end
