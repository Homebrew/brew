# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/uv"

RSpec.describe Homebrew::Bundle::Uv do
  describe "checking" do
    subject(:checker) { described_class.new }

    describe "#installed_and_up_to_date?" do
      it "returns false when package is not installed" do
        allow(described_class).to receive(:package_installed?).and_return(false)
        expect(
          checker.installed_and_up_to_date?(
            { name: "mkdocs", options: { with: ["mkdocs-material<10"] } },
          ),
        ).to be(false)
      end

      it "returns true when package and options match" do
        expect(described_class).to receive(:package_installed?)
          .with("mkdocs", with: ["mkdocs-material<10"])
          .and_return(true)

        expect(
          checker.installed_and_up_to_date?(
            { name: "mkdocs", options: { with: ["mkdocs-material<10"] } },
          ),
        ).to be(true)
      end
    end

    describe "#failure_reason" do
      it "returns a package-specific message" do
        expect(
          checker.failure_reason({ name: "mkdocs", options: { with: ["mkdocs-material<10"] } }, no_upgrade: false),
        ).to eq("uv Tool mkdocs needs to be installed.")
      end
    end

    describe "#find_actionable" do
      let(:entries) do
        [
          Homebrew::Bundle::Dsl::Entry.new(:uv, "ruff"),
          Homebrew::Bundle::Dsl::Entry.new(:uv, "mkdocs", with: ["mkdocs-material<10"]),
          Homebrew::Bundle::Dsl::Entry.new(:brew, "wget"),
        ]
      end

      it "checks uv entries and passes normalized options to installer checks" do
        expect(described_class).to receive(:package_installed?)
          .with("ruff", with: [])
          .and_return(true)
        expect(described_class).to receive(:package_installed?)
          .with("mkdocs", with: ["mkdocs-material<10"])
          .and_return(true)

        actionable = checker.find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        expect(actionable).to eq([])
      end

      it "returns missing uv tools from full check flow" do
        allow(described_class).to receive(:package_installed?) do |name, **|
          name == "ruff"
        end

        actionable = checker.find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        expect(actionable).to eq(["uv Tool mkdocs needs to be installed."])
      end
    end
  end

  describe "dumping" do
    subject(:dumper) { described_class }

    let(:uv_tool_list_command) do
      [
        "uv tool list",
        "--show-with",
        "--show-extras",
        "2>/dev/null",
      ].join(" ")
    end

    context "when uv is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "returns empty packages and dump output" do
        expect(dumper.packages).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "when uv is installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("uv"))
      end

      it "returns normalized package entries sorted by package name" do
        allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
          ruff v0.14.14
          - ruff
          mkdocs v1.6.1 [with: mkdocs-material<10]
          - mkdocs
        OUTPUT

        expect(dumper.packages).to eql([
          {
            name: "mkdocs",
            with: ["mkdocs-material<10"],
          },
          {
            name: "ruff",
            with: [],
          },
        ])
      end

      it "dumps correct Brewfile entries" do
        allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
          ruff v0.14.14 [with: httpx>=0.27]
          - ruff
        OUTPUT

        expect(dumper.dump).to eql('uv "ruff", with: ["httpx>=0.27"]')
      end

      it "handles tools with no optional metadata" do
        allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
          ruff v0.14.14
          - ruff
        OUTPUT

        expect(dumper.dump).to eql('uv "ruff"')
      end

      it "returns empty packages when no tools are installed" do
        allow(described_class).to receive(:`).with(uv_tool_list_command).and_return("")

        expect(dumper.packages).to be_empty
        expect(dumper.dump).to eql("")
      end

      it "handles multiple with dependencies" do
        allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
          mkdocs v1.6.1 [with: mkdocs-material, mkdocs-awesome-page-plugin]
          - mkdocs
        OUTPUT

        expect(dumper.packages.first&.dig(:with)).to eql(["mkdocs-awesome-page-plugin", "mkdocs-material"])
      end

      it "keeps comma-constrained with requirements as a single requirement" do
        allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
          ruff v0.14.14 [with: httpx>=0.27, <0.29]
          - ruff
        OUTPUT

        expect(dumper.packages.first&.dig(:with)).to eql(["httpx>=0.27, <0.29"])
        expect(dumper.dump).to eql('uv "ruff", with: ["httpx>=0.27, <0.29"]')
      end

      it "preserves extras for the main tool requirement" do
        allow(described_class).to receive(:`).with(uv_tool_list_command).and_return(<<~OUTPUT)
          fastapi v0.129.0 [extras: all, standard]
          - fastapi
        OUTPUT

        expect(dumper.packages.first).to include(name: "fastapi[all,standard]")
        expect(dumper.dump).to eql('uv "fastapi[all,standard]"')
      end
    end
  end

  describe "installing" do
    context "when uv is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "tries to install uv" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "uv", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("mkdocs") }.to raise_error(RuntimeError)
      end
    end

    context "when uv is installed" do
      before do
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("uv"))
      end

      context "when package is installed with matching options" do
        before do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name: "mkdocs",
              with: ["mkdocs-material<10"],
            },
          ])
        end

        it "skips install" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("mkdocs", with: ["mkdocs-material<10"])).to be(false)
        end

        it "skips install for package with no options" do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name: "ruff",
              with: [],
            },
          ])

          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("ruff")).to be(false)
        end

        it "treats matching with requirements as installed" do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name: "ruff",
              with: ["httpx>=0.27"],
            },
          ])

          expect(
            described_class.package_installed?(
              "ruff",
              with: ["httpx>=0.27"],
            ),
          ).to be(true)
        end

        it "treats extras with different ordering as installed" do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name: "fastapi[all,standard]",
              with: [],
            },
          ])

          expect(
            described_class.package_installed?(
              "fastapi[standard,all]",
            ),
          ).to be(true)
        end
      end

      context "when package is installed but with options differ" do
        before do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name: "mkdocs",
              with: ["mkdocs-material<10"],
            },
          ])
        end

        it "does not treat mismatched with dependencies as installed" do
          expect(described_class.package_installed?("mkdocs", with: ["mkdocs-material<9"])).to be(false)
        end
      end

      context "when package is not installed" do
        before do
          allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("/tmp/uv/bin/uv"))
          allow(described_class).to receive_messages(packages: [], installed_packages: [])
        end

        it "installs package with no options" do
          expect(Homebrew::Bundle).to receive(:system)
            .with("/tmp/uv/bin/uv", "tool", "install", "ruff", verbose: false).and_return(true)

          expect(described_class.preinstall!("ruff")).to be(true)
          expect(described_class.install!("ruff")).to be(true)
        end

        it "installs package with all supported options" do
          expect(Homebrew::Bundle).to receive(:system)
            .with("/tmp/uv/bin/uv", "tool", "install", "mkdocs",
                  "--with", "mkdocs-material<10",
                  verbose: false).and_return(true)

          expect(described_class.preinstall!("mkdocs", with: ["mkdocs-material<10"])).to be(true)
          expect(described_class.install!("mkdocs", with: ["mkdocs-material<10"])).to be(true)
        end

        it "updates dump output after install in the same process" do
          expect(Homebrew::Bundle).to receive(:system)
            .with("/tmp/uv/bin/uv", "tool", "install", "mkdocs",
                  "--with", "mkdocs-material<10",
                  verbose: false).and_return(true)

          described_class.install!("mkdocs", with: ["mkdocs-material<10"])

          expect(described_class.dump).to eql('uv "mkdocs", with: ["mkdocs-material<10"]')
        end
      end
    end
  end

  describe "cleanup" do
    before do
      described_class.reset!
      tools = [
        { name: "ruff", with: [] },
        { name: "mkdocs", with: ["mkdocs-material<10"] },
        { name: "black", with: [] },
      ]
      allow(described_class).to receive_messages(
        package_manager_executable: Pathname.new("/tmp/uv/bin/uv"),
        packages:                   tools,
        installed_packages:         tools,
      )
    end

    it "returns tools not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:uv, "ruff")]
      expect(described_class.cleanup_items(entries)).to eql(%w[mkdocs black])
    end

    it "returns frozen empty array when uv is not installed" do
      allow(described_class).to receive(:package_manager_installed?).and_return(false)
      entries = [Homebrew::Bundle::Dsl::Entry.new(:uv, "ruff")]
      expect(described_class.cleanup_items(entries)).to eql([])
    end
  end
end
