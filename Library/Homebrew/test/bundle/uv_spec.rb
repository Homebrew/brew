# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/shared_examples/inventory"
require "bundle/dumper"
require "bundle/extensions/uv"

RSpec.describe Homebrew::Bundle::Uv do
  let(:inventory_output) { "example-tool v1.0 [required: https://example.com/café.whl]\n" }
  let(:inventory_records) { [{ name: "example-tool", with: [], source: "https://example.com/café.whl" }] }

  it_behaves_like "a checked package inventory"
  it_behaves_like "a checked inventory", :installed_packages

  def stub_tool_list(output)
    allow(SystemCommand).to receive(:run!)
      .with(Pathname("uv"),
            args:         ["tool", "list", "--show-with", "--show-extras", "--show-version-specifiers"],
            print_stderr: false)
      .and_return(instance_double(SystemCommand::Result, stdout: output))
  end

  describe "entries" do
    it "accepts a source that resolves on another machine" do
      entry = described_class.entry("other-tool", source: "git+https://example.com/tools/other-tool.git")
      expect(entry.options).to eql({ source: "git+https://example.com/tools/other-tool.git" })
    end

    it "rejects a local path" do
      expect { described_class.entry("local-tool", source: "/Users/test/src/local-tool") }
        .to raise_error(RuntimeError, /local to this machine/)
    end

    it "rejects the file:// URL uv reports for a directory install" do
      expect { described_class.entry("local-tool", source: "file:///Users/test/src/local-tool") }
        .to raise_error(RuntimeError, /local to this machine/)
    end

    it "rejects a git+file:// URL" do
      expect { described_class.entry("local-tool", source: "git+file:///Users/test/src/local-tool") }
        .to raise_error(RuntimeError, /local to this machine/)
    end
  end

  describe "checking" do
    subject(:checker) { described_class.new }

    describe "#installed_and_up_to_date?" do
      it "returns false when package is not installed" do
        allow(described_class).to receive(:package_installed?).and_return(false)
        expect(
          checker.installed_and_up_to_date?(
            { name: "example-tool", options: { with: ["example-dependency<10"] } },
          ),
        ).to be(false)
      end

      it "returns true when package and options match" do
        expect(described_class).to receive(:package_installed?)
          .with("example-tool", with: ["example-dependency<10"], source: nil)
          .and_return(true)

        expect(
          checker.installed_and_up_to_date?(
            { name: "example-tool", options: { with: ["example-dependency<10"] } },
          ),
        ).to be(true)
      end

      it "passes the source through when checking a tool installed from a source" do
        expect(described_class).to receive(:package_installed?)
          .with("other-tool", with: [], source: "git+https://example.com/tools/other-tool.git")
          .and_return(true)

        expect(
          checker.installed_and_up_to_date?(
            { name:    "other-tool",
              options: { source: "git+https://example.com/tools/other-tool.git" } },
          ),
        ).to be(true)
      end
    end

    describe "#failure_reason" do
      it "returns a package-specific message" do
        expect(
          checker.failure_reason({ name: "example-tool", options: { with: ["example-dependency<10"] } },
                                 no_upgrade: false),
        ).to eq("uv Tool example-tool needs to be installed.")
      end
    end

    describe "#find_actionable" do
      let(:entries) do
        [
          Homebrew::Bundle::Dsl::Entry.new(:uv, "other-tool"),
          Homebrew::Bundle::Dsl::Entry.new(:uv, "example-tool", with: ["example-dependency<10"]),
          Homebrew::Bundle::Dsl::Entry.new(:brew, "example-formula"),
        ]
      end

      it "checks uv entries and passes normalized options to installer checks" do
        expect(described_class).to receive(:package_installed?)
          .with("other-tool", with: [], source: nil)
          .and_return(true)
        expect(described_class).to receive(:package_installed?)
          .with("example-tool", with: ["example-dependency<10"], source: nil)
          .and_return(true)

        actionable = checker.find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        expect(actionable).to eq([])
      end

      it "returns missing uv tools from full check flow" do
        allow(described_class).to receive(:package_installed?) do |name, **|
          name == "other-tool"
        end

        actionable = checker.find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        expect(actionable).to eq(["uv Tool example-tool needs to be installed."])
      end
    end
  end

  describe "dumping" do
    subject(:dumper) { described_class }

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
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname("uv"))
      end

      it "returns normalized package entries sorted by package name" do
        stub_tool_list(<<~OUTPUT)
          other-tool v0.14.14
          - other-tool
          example-tool v1.6.1 [with: example-dependency<10]
          - example-tool
        OUTPUT

        expect(dumper.packages).to eq([
          {
            name:   "example-tool",
            with:   ["example-dependency<10"],
            source: nil,
          },
          {
            name:   "other-tool",
            with:   [],
            source: nil,
          },
        ])
      end

      it "ignores executable entries when dumping packages" do
        stub_tool_list(<<~OUTPUT)
          v-example v1.2.3
          - v-example
          - v2
          v-other-tool v2.16
          - v-other-tool
        OUTPUT

        expect(dumper.dump).to eq(<<~BREWFILE.chomp)
          uv "v-example"
          uv "v-other-tool"
        BREWFILE
      end

      it "accepts headings with valid package-name forms and version strings" do
        stub_tool_list(<<~OUTPUT)
          a v1.0
          7tool v1!2.0rc1+local
          my-tool.name_2 v2.0
          Vtool v1.0
        OUTPUT

        expect(dumper.dump).to eq(<<~BREWFILE.chomp)
          uv "7tool"
          uv "Vtool"
          uv "a"
          uv "my-tool.name_2"
        BREWFILE
      end

      it "ignores lines whose first token starts with punctuation" do
        stub_tool_list(<<~OUTPUT)
          v-other-tool v2.16
          -\tv2
          • v2
          _vtool v1.0
        OUTPUT

        expect(dumper.dump).to eq('uv "v-other-tool"')
      end

      it "parses a git source from the version specifier and dumps it" do
        stub_tool_list(<<~OUTPUT)
          other-tool v0.14.14 [required:  git+https://example.com/tools/other-tool.git]
          - other-tool
        OUTPUT

        expect(dumper.packages).to eq([
          {
            name:   "other-tool",
            with:   [],
            source: "git+https://example.com/tools/other-tool.git",
          },
        ])
        expect(dumper.dump).to eq('uv "other-tool", source: "git+https://example.com/tools/other-tool.git"')
      end

      it "dumps a tool installed from a directory without a source" do
        stub_tool_list(<<~OUTPUT)
          local-tool v0.1.0 [required: file:///Users/test/src/local-tool]
          - local-tool
        OUTPUT

        expect(dumper.dump).to eq('uv "local-tool"')
      end

      it "dumps a tool installed from a git+file:// URL without a source" do
        stub_tool_list(<<~OUTPUT)
          local-tool v0.1.0 [required: git+file:///Users/test/src/local-tool]
          - local-tool
        OUTPUT

        expect(dumper.dump).to eq('uv "local-tool"')
      end

      it "dumps a tool installed from a directory named like a git repository without a source" do
        stub_tool_list(<<~OUTPUT)
          local-tool v0.1.0 [required: file:///Users/test/src/local-tool.git]
          - local-tool
        OUTPUT

        expect(dumper.dump).to eq('uv "local-tool"')
      end

      it "ignores a bare version constraint in the version specifier" do
        stub_tool_list(<<~OUTPUT)
          other-tool v0.14.14 [required: >=0.1]
          - other-tool
        OUTPUT

        expect(dumper.packages.first&.dig(:source)).to be_nil
        expect(dumper.dump).to eq('uv "other-tool"')
      end

      it "dumps both with and source segments" do
        stub_tool_list(<<~OUTPUT)
          other-tool v0.14.14 [with: example-dependency>=0.27] [required: git+https://example.com/tools/other-tool.git]
          - other-tool
        OUTPUT

        expect(dumper.dump).to eq(
          'uv "other-tool", with: ["example-dependency>=0.27"], source: "git+https://example.com/tools/other-tool.git"',
        )
      end

      it "dumps correct Brewfile entries" do
        stub_tool_list(<<~OUTPUT)
          other-tool v0.14.14 [with: example-dependency>=0.27]
          - other-tool
        OUTPUT

        expect(dumper.dump).to eq('uv "other-tool", with: ["example-dependency>=0.27"]')
      end

      it "handles tools with no optional metadata" do
        stub_tool_list(<<~OUTPUT)
          other-tool v0.14.14
          - other-tool
        OUTPUT

        expect(dumper.dump).to eq('uv "other-tool"')
      end

      it "returns empty packages when no tools are installed" do
        stub_tool_list("")

        expect(dumper.packages).to be_empty
        expect(dumper.dump).to eq("")
      end

      it "handles multiple with dependencies" do
        stub_tool_list(<<~OUTPUT)
          example-tool v1.6.1 [with: example-dependency, another-dependency]
          - example-tool
        OUTPUT

        expect(dumper.packages.first&.dig(:with)).to eq(["another-dependency", "example-dependency"])
      end

      it "keeps comma-constrained with requirements as a single requirement" do
        stub_tool_list(<<~OUTPUT)
          other-tool v0.14.14 [with: example-dependency>=0.27, <0.29]
          - other-tool
        OUTPUT

        expect(dumper.packages.first&.dig(:with)).to eq(["example-dependency>=0.27, <0.29"])
        expect(dumper.dump).to eq('uv "other-tool", with: ["example-dependency>=0.27, <0.29"]')
      end

      it "preserves extras for the main tool requirement" do
        stub_tool_list(<<~OUTPUT)
          example-tool v0.129.0 [extras: all, standard]
          - example-tool
        OUTPUT

        expect(dumper.packages.first).to include(name: "example-tool[all,standard]")
        expect(dumper.dump).to eq('uv "example-tool[all,standard]"')
      end
    end
  end

  describe "installing" do
    before do
      ENV.delete("UV_PYTHON")
      allow(Formula).to receive(:installed_formula_names).and_return([])
      allow(Formula).to receive(:[]).and_raise("Python selection must not load formulae")
    end

    context "when uv is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "tries to install uv" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "uv", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("example-tool") }.to raise_error(RuntimeError)
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
              name:   "example-tool",
              with:   ["example-dependency<10"],
              source: nil,
            },
          ])
        end

        it "skips install" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("example-tool", with: ["example-dependency<10"])).to be(false)
        end

        it "skips install for package with no options" do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name:   "other-tool",
              with:   [],
              source: nil,
            },
          ])

          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("other-tool")).to be(false)
        end

        it "treats matching with requirements as installed" do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name:   "other-tool",
              with:   ["example-dependency>=0.27"],
              source: nil,
            },
          ])

          expect(
            described_class.package_installed?(
              "other-tool",
              with: ["example-dependency>=0.27"],
            ),
          ).to be(true)
        end

        it "treats a matching source as installed" do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name:   "other-tool",
              with:   [],
              source: "git+https://example.com/tools/other-tool.git",
            },
          ])

          expect(
            described_class.package_installed?(
              "other-tool",
              source: "git+https://example.com/tools/other-tool.git",
            ),
          ).to be(true)
        end

        it "treats extras with different ordering as installed" do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name:   "example-tool[all,standard]",
              with:   [],
              source: nil,
            },
          ])

          expect(
            described_class.package_installed?(
              "example-tool[standard,all]",
            ),
          ).to be(true)
        end
      end

      context "when package is installed but with options differ" do
        before do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name:   "example-tool",
              with:   ["example-dependency<10"],
              source: nil,
            },
          ])
        end

        it "does not treat mismatched with dependencies as installed" do
          expect(described_class.package_installed?("example-tool", with: ["example-dependency<9"])).to be(false)
        end
      end

      context "when package is installed from a different source" do
        before do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name:   "other-tool",
              with:   [],
              source: "git+https://example.com/tools/other-tool.git",
            },
          ])
        end

        it "does not treat a different source as installed" do
          expect(
            described_class.package_installed?("other-tool", source: "other-tool"),
          ).to be(false)
        end
      end

      context "when package is not installed" do
        before do
          allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("/tmp/uv/bin/uv"))
          allow(described_class).to receive_messages(packages: [], installed_packages: [])
        end

        it "installs package with no options" do
          expect(Homebrew::Bundle).to receive(:system)
            .with("/tmp/uv/bin/uv", "tool", "install", "other-tool", verbose: false).and_return(true)

          expect(described_class.preinstall!("other-tool")).to be(true)
          expect(described_class.install!("other-tool")).to be(true)
        end

        it "uses the newest installed Homebrew Python" do
          allow(Formula).to receive(:installed_formula_names)
            .and_return(%w[python@3.9 python@3.14 python@3.15 python-tk@3.16])
          %w[python@3.9/bin/python3.9 python@3.14/bin/python3.14 python@3.14/bin/python3.99-config
             python-tk@3.16/bin/python3.16].each do |path|
            python = HOMEBREW_PREFIX/"opt"/path
            python.dirname.mkpath
            python.write ""
          end
          allow(Homebrew::Bundle).to receive(:system) do
            expect(ENV.fetch("UV_PYTHON", nil)).to eq("#{HOMEBREW_PREFIX}/opt/python@3.14/bin/python3.14")
            true
          end

          described_class.install!("other-tool")
        end

        it "uses an installed versioned Homebrew Python" do
          allow(Formula).to receive(:installed_formula_names).and_return(["python@3"])
          (HOMEBREW_PREFIX/"opt/python@3/bin").mkpath
          (HOMEBREW_PREFIX/"opt/python@3/bin/python3.12").write ""
          allow(Homebrew::Bundle).to receive(:system) do
            expect(ENV.fetch("UV_PYTHON", nil)).to eq("#{HOMEBREW_PREFIX}/opt/python@3/bin/python3.12")
            true
          end

          described_class.install!("other-tool")
        end

        it "includes the unversioned Python formula" do
          allow(Formula).to receive(:installed_formula_names).and_return(%w[python python@3.13])
          %w[python/bin/python3.14 python@3.13/bin/python3.13].each do |path|
            python = HOMEBREW_PREFIX/"opt"/path
            python.dirname.mkpath
            python.write ""
          end
          allow(Homebrew::Bundle).to receive(:system) do
            expect(ENV.fetch("UV_PYTHON", nil)).to eq("#{HOMEBREW_PREFIX}/opt/python/bin/python3.14")
            true
          end

          described_class.install!("other-tool")
        end

        it "installs package with all supported options" do
          expect(Homebrew::Bundle).to receive(:system)
            .with("/tmp/uv/bin/uv", "tool", "install", "example-tool",
                  "--with", "example-dependency<10",
                  verbose: false).and_return(true)

          expect(described_class.preinstall!("example-tool", with: ["example-dependency<10"])).to be(true)
          expect(described_class.install!("example-tool", with: ["example-dependency<10"])).to be(true)
        end

        it "installs a package from its source" do
          source = "git+https://example.com/tools/other-tool.git"
          expect(Homebrew::Bundle).to receive(:system)
            .with("/tmp/uv/bin/uv", "tool", "install", source, verbose: false).and_return(true)

          expect(described_class.preinstall!("other-tool", source:)).to be(true)
          expect(described_class.install!("other-tool", source:)).to be(true)
        end

        it "updates dump output after install in the same process" do
          expect(Homebrew::Bundle).to receive(:system)
            .with("/tmp/uv/bin/uv", "tool", "install", "example-tool",
                  "--with", "example-dependency<10",
                  verbose: false).and_return(true)

          described_class.install!("example-tool", with: ["example-dependency<10"])

          expect(described_class.dump).to eql('uv "example-tool", with: ["example-dependency<10"]')
        end
      end
    end
  end

  describe "consumers of parsed tool lists" do
    before do
      described_class.reset!
      allow(described_class).to receive(:package_manager_executable).and_return(Pathname("uv"))
      stub_tool_list(<<~OUTPUT)
        v-other-tool v2.16 [required: git+https://example.com/v-other-tool.git] [extras: cli] [with: example-dependency>=0.27]
        - v-other-tool
        - v2
        other-tool v0.14.14
        - other-tool
      OUTPUT
    end

    it "checks installed entries using parsed names and metadata" do
      entries = [
        Homebrew::Bundle::Dsl::Entry.new(:uv, "v-other-tool[cli]", with:   ["example-dependency>=0.27"],
                                                                   source: "git+https://example.com/v-other-tool.git"),
        Homebrew::Bundle::Dsl::Entry.new(:uv, "-"),
      ]

      expect(described_class.check(entries)).to eq(["uv Tool - needs to be installed."])
    end

    it "selects only undeclared packages for cleanup" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:uv, "v-other-tool[cli]")]

      expect(described_class.cleanup_items(entries)).to eq(["other-tool"])
    end
  end

  describe "cleanup" do
    before do
      described_class.reset!
      tools = [
        { name: "other-tool", with: [] },
        { name: "example-tool", with: ["example-dependency<10"] },
        { name: "another-tool", with: [] },
      ]
      allow(described_class).to receive_messages(
        package_manager_executable: Pathname.new("/tmp/uv/bin/uv"),
        packages:                   tools,
        installed_packages:         tools,
      )
    end

    it "returns tools not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:uv, "other-tool")]
      expect(described_class.cleanup_items(entries)).to eql(%w[example-tool another-tool])
    end

    it "returns the uninstall command result" do
      allow(Homebrew::Bundle).to receive(:system)
        .with("/tmp/uv/bin/uv", "tool", "uninstall", "example", verbose: false).and_return(false)

      expect(
        described_class.uninstall_package!("example", executable: Pathname("/tmp/uv/bin/uv")),
      ).to be(false)
    end

    it "preserves PATH when uninstalling tools" do
      ENV["PATH"] = "/existing/bin"
      uninstall_path = ""
      allow(Homebrew::Bundle).to receive(:system)
        .with("/tmp/uv/bin/uv", "tool", "uninstall", "example", verbose: false) do
          uninstall_path = ENV.fetch("PATH")
          true
        end
      allow(described_class).to receive(:puts)

      described_class.cleanup!(["example"])

      expect(uninstall_path).to eq("/existing/bin")
    end

    it "returns frozen empty array when uv is not installed" do
      allow(described_class).to receive(:package_manager_installed?).and_return(false)
      entries = [Homebrew::Bundle::Dsl::Entry.new(:uv, "other-tool")]
      expect(described_class.cleanup_items(entries)).to eql([])
    end
  end
end
