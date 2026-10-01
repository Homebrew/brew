# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/uv"

RSpec.describe Homebrew::Bundle::Uv do
  let(:uv_tool_list_args) do
    [Pathname("uv"), "tool", "list", "--show-with", "--show-extras", "--show-version-specifiers"]
  end

  describe "entries" do
    it "accepts a source that resolves on another machine" do
      entry = described_class.entry("ruff", source: "git+https://github.com/astral-sh/ruff.git")
      expect(entry.options).to eql({ source: "git+https://github.com/astral-sh/ruff.git" })
    end

    it "rejects a local path" do
      expect { described_class.entry("probetool", source: "/Users/test/src/probetool") }
        .to raise_error(RuntimeError, /local to this machine/)
    end

    it "rejects the file:// URL uv reports for a directory install" do
      expect { described_class.entry("probetool", source: "file:///Users/test/src/probetool") }
        .to raise_error(RuntimeError, /local to this machine/)
    end

    it "rejects a git+file:// URL" do
      expect { described_class.entry("probetool", source: "git+file:///Users/test/src/probetool") }
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
            { name: "mkdocs", options: { with: ["mkdocs-material<10"] } },
          ),
        ).to be(false)
      end

      it "returns true when package and options match" do
        expect(described_class).to receive(:package_installed?)
          .with("mkdocs", with: ["mkdocs-material<10"], source: nil)
          .and_return(true)

        expect(
          checker.installed_and_up_to_date?(
            { name: "mkdocs", options: { with: ["mkdocs-material<10"] } },
          ),
        ).to be(true)
      end

      it "passes the source through when checking a tool installed from a source" do
        expect(described_class).to receive(:package_installed?)
          .with("ruff", with: [], source: "git+https://github.com/astral-sh/ruff.git")
          .and_return(true)

        expect(
          checker.installed_and_up_to_date?(
            { name:    "ruff",
              options: { source: "git+https://github.com/astral-sh/ruff.git" } },
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
          .with("ruff", with: [], source: nil)
          .and_return(true)
        expect(described_class).to receive(:package_installed?)
          .with("mkdocs", with: ["mkdocs-material<10"], source: nil)
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
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          ruff v0.14.14
          - ruff
          mkdocs v1.6.1 [with: mkdocs-material<10]
          - mkdocs
        OUTPUT

        expect(dumper.packages).to eql([
          {
            name:   "mkdocs",
            with:   ["mkdocs-material<10"],
            source: nil,
          },
          {
            name:   "ruff",
            with:   [],
            source: nil,
          },
        ])
      end

      it "ignores executable entries when dumping packages" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          v-example v1.2.3
          - v-example
          - v2
          vulture v2.16
          - vulture
        OUTPUT

        expect(dumper.dump).to eql(<<~BREWFILE.chomp)
          uv "v-example"
          uv "vulture"
        BREWFILE
      end

      it "accepts headings with valid package-name forms and version strings" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          a v1.0
          7zip v1!2.0rc1+local
          my-tool.name_2 v2.0
          Vtool v1.0
        OUTPUT

        expect(dumper.dump).to eql(<<~BREWFILE.chomp)
          uv "7zip"
          uv "Vtool"
          uv "a"
          uv "my-tool.name_2"
        BREWFILE
      end

      it "ignores lines whose first token starts with punctuation" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL)
                                                 .and_return("vulture v2.16\n-\tv2\n• v2\n_vtool v1.0\n")

        expect(dumper.dump).to eql('uv "vulture"')
      end

      it "parses a git source from the version specifier and dumps it" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          ruff v0.14.14 [required:  git+https://github.com/astral-sh/ruff.git]
          - ruff
        OUTPUT

        expect(dumper.packages).to eql([
          {
            name:   "ruff",
            with:   [],
            source: "git+https://github.com/astral-sh/ruff.git",
          },
        ])
        expect(dumper.dump).to eql('uv "ruff", source: "git+https://github.com/astral-sh/ruff.git"')
      end

      it "dumps a tool installed from a directory without a source" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          probetool v0.1.0 [required: file:///Users/test/src/probetool]
          - probetool
        OUTPUT

        expect(dumper.dump).to eql('uv "probetool"')
      end

      it "dumps a tool installed from a git+file:// URL without a source" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          probetool v0.1.0 [required: git+file:///Users/test/src/probetool]
          - probetool
        OUTPUT

        expect(dumper.dump).to eql('uv "probetool"')
      end

      it "dumps a tool installed from a directory named like a git repository without a source" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          probetool v0.1.0 [required: file:///Users/test/src/probetool.git]
          - probetool
        OUTPUT

        expect(dumper.dump).to eql('uv "probetool"')
      end

      it "ignores a bare version constraint in the version specifier" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          ruff v0.14.14 [required: >=0.1]
          - ruff
        OUTPUT

        expect(dumper.packages.first&.dig(:source)).to be_nil
        expect(dumper.dump).to eql('uv "ruff"')
      end

      it "dumps both with and source segments" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          ruff v0.14.14 [with: httpx>=0.27] [required: git+https://github.com/astral-sh/ruff.git]
          - ruff
        OUTPUT

        expect(dumper.dump).to eql(
          'uv "ruff", with: ["httpx>=0.27"], source: "git+https://github.com/astral-sh/ruff.git"',
        )
      end

      it "dumps correct Brewfile entries" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          ruff v0.14.14 [with: httpx>=0.27]
          - ruff
        OUTPUT

        expect(dumper.dump).to eql('uv "ruff", with: ["httpx>=0.27"]')
      end

      it "handles tools with no optional metadata" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          ruff v0.14.14
          - ruff
        OUTPUT

        expect(dumper.dump).to eql('uv "ruff"')
      end

      it "returns empty packages when no tools are installed" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return("")

        expect(dumper.packages).to be_empty
        expect(dumper.dump).to eql("")
      end

      it "handles multiple with dependencies" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          mkdocs v1.6.1 [with: mkdocs-material, mkdocs-awesome-page-plugin]
          - mkdocs
        OUTPUT

        expect(dumper.packages.first&.dig(:with)).to eql(["mkdocs-awesome-page-plugin", "mkdocs-material"])
      end

      it "keeps comma-constrained with requirements as a single requirement" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          ruff v0.14.14 [with: httpx>=0.27, <0.29]
          - ruff
        OUTPUT

        expect(dumper.packages.first&.dig(:with)).to eql(["httpx>=0.27, <0.29"])
        expect(dumper.dump).to eql('uv "ruff", with: ["httpx>=0.27, <0.29"]')
      end

      it "preserves extras for the main tool requirement" do
        allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
          fastapi v0.129.0 [extras: all, standard]
          - fastapi
        OUTPUT

        expect(dumper.packages.first).to include(name: "fastapi[all,standard]")
        expect(dumper.dump).to eql('uv "fastapi[all,standard]"')
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
              name:   "mkdocs",
              with:   ["mkdocs-material<10"],
              source: nil,
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
              name:   "ruff",
              with:   [],
              source: nil,
            },
          ])

          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("ruff")).to be(false)
        end

        it "treats matching with requirements as installed" do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name:   "ruff",
              with:   ["httpx>=0.27"],
              source: nil,
            },
          ])

          expect(
            described_class.package_installed?(
              "ruff",
              with: ["httpx>=0.27"],
            ),
          ).to be(true)
        end

        it "treats a matching source as installed" do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name:   "ruff",
              with:   [],
              source: "git+https://github.com/astral-sh/ruff.git",
            },
          ])

          expect(
            described_class.package_installed?(
              "ruff",
              source: "git+https://github.com/astral-sh/ruff.git",
            ),
          ).to be(true)
        end

        it "treats extras with different ordering as installed" do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name:   "fastapi[all,standard]",
              with:   [],
              source: nil,
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
              name:   "mkdocs",
              with:   ["mkdocs-material<10"],
              source: nil,
            },
          ])
        end

        it "does not treat mismatched with dependencies as installed" do
          expect(described_class.package_installed?("mkdocs", with: ["mkdocs-material<9"])).to be(false)
        end
      end

      context "when package is installed from a different source" do
        before do
          allow(described_class).to receive(:installed_packages).and_return([
            {
              name:   "ruff",
              with:   [],
              source: "git+https://github.com/astral-sh/ruff.git",
            },
          ])
        end

        it "does not treat a different source as installed" do
          expect(
            described_class.package_installed?("ruff", source: "ruff"),
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
            .with("/tmp/uv/bin/uv", "tool", "install", "ruff", verbose: false).and_return(true)

          expect(described_class.preinstall!("ruff")).to be(true)
          expect(described_class.install!("ruff")).to be(true)
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

          described_class.install!("ruff")
        end

        it "uses an installed versioned Homebrew Python" do
          allow(Formula).to receive(:installed_formula_names).and_return(["python@3"])
          (HOMEBREW_PREFIX/"opt/python@3/bin").mkpath
          (HOMEBREW_PREFIX/"opt/python@3/bin/python3.12").write ""
          allow(Homebrew::Bundle).to receive(:system) do
            expect(ENV.fetch("UV_PYTHON", nil)).to eq("#{HOMEBREW_PREFIX}/opt/python@3/bin/python3.12")
            true
          end

          described_class.install!("ruff")
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

          described_class.install!("ruff")
        end

        it "installs package with all supported options" do
          expect(Homebrew::Bundle).to receive(:system)
            .with("/tmp/uv/bin/uv", "tool", "install", "mkdocs",
                  "--with", "mkdocs-material<10",
                  verbose: false).and_return(true)

          expect(described_class.preinstall!("mkdocs", with: ["mkdocs-material<10"])).to be(true)
          expect(described_class.install!("mkdocs", with: ["mkdocs-material<10"])).to be(true)
        end

        it "installs a package from its source" do
          source = "git+https://github.com/astral-sh/ruff.git"
          expect(Homebrew::Bundle).to receive(:system)
            .with("/tmp/uv/bin/uv", "tool", "install", source, verbose: false).and_return(true)

          expect(described_class.preinstall!("ruff", source:)).to be(true)
          expect(described_class.install!("ruff", source:)).to be(true)
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

  describe "consumers of parsed tool lists" do
    before do
      described_class.reset!
      allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("uv"))
      allow(Utils).to receive(:popen_read_text).with(*uv_tool_list_args, err: File::NULL).and_return(<<~OUTPUT)
        vulture v2.16 [required: git+https://example.com/vulture.git] [extras: cli] [with: httpx>=0.27]
        - vulture
        - v2
        ruff v0.14.14
        - ruff
      OUTPUT
    end

    it "checks installed entries using parsed names and metadata" do
      entries = [
        Homebrew::Bundle::Dsl::Entry.new(:uv, "vulture[cli]", with:   ["httpx>=0.27"],
                                                              source: "git+https://example.com/vulture.git"),
        Homebrew::Bundle::Dsl::Entry.new(:uv, "-"),
      ]

      expect(described_class.check(entries)).to eql(["uv Tool - needs to be installed."])
    end

    it "selects only undeclared packages for cleanup" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:uv, "vulture[cli]")]

      expect(described_class.cleanup_items(entries)).to eql(["ruff"])
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
