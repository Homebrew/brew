# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/shared_examples/inventory"
require "bundle/extensions/cargo"

RSpec.describe Homebrew::Bundle::Cargo do
  let(:inventory_output) { "example-tool v1.0\n    example-tool\n" }
  let(:inventory_records) { [{ name: "example-tool", source: nil }] }

  around do |example|
    with_env({
      "HOMEBREW_CARGO_HOME"         => "~/.cargo",
      "HOMEBREW_CARGO_INSTALL_ROOT" => "~/.cargo/bin",
      "HOMEBREW_RUSTUP_HOME"        => "~/.rustup",
      "CARGO_HOME"                  => nil,
      "CARGO_INSTALL_ROOT"          => nil,
      "RUSTUP_HOME"                 => nil,
    }) do
      example.run
    end
  end

  it_behaves_like "a checked package inventory", stderr_forwarded: true
  it_behaves_like "a checked inventory", :installed_packages, stderr_forwarded: true

  def stub_cargo_list(output)
    allow(described_class).to receive(:command_output)
      .with(Pathname("cargo"), args: ["install", "--list"], print_stderr: true).and_return(output)
  end

  describe "entries" do
    it "accepts a source option" do
      entry = described_class.entry("source-tool", source: "ssh://git@example.com/tools/example-repo.git")
      expect(entry.name).to eql("source-tool")
      expect(entry.options).to eql({ source: "ssh://git@example.com/tools/example-repo.git" })
    end

    it "accepts a source that selects a git reference" do
      entry = described_class.entry("source-tool", source: "ssh://git@example.com/tools/example-repo.git?branch=next")
      expect(entry.options).to eql({ source: "ssh://git@example.com/tools/example-repo.git?branch=next" })
    end

    it "stores no options when no source is given" do
      expect(described_class.entry("third-tool").options).to be_empty
    end

    it "rejects a non-String source" do
      expect { described_class.entry("source-tool", source: ["ssh://git@example.com/tools/example-repo.git"]) }
        .to raise_error(RuntimeError, /options\[:source\]/)
    end

    it "rejects a source that is not a git URL" do
      expect { described_class.entry("source-tool", source: "source-tool") }
        .to raise_error(RuntimeError, /should be a git URL/)
    end

    it "rejects a local path, which does not resolve on another machine" do
      expect { described_class.entry("example-tool", source: "/Users/test/src/example-tool") }
        .to raise_error(RuntimeError, /should be a git URL/)
    end

    it "rejects a file:// git URL, which does not resolve on another machine either" do
      expect { described_class.entry("example-tool", source: "file:///Users/test/src/example-tool") }
        .to raise_error(RuntimeError, /should be a git URL/)
    end

    it "rejects a git query that selects something other than a branch, tag or rev" do
      expect { described_class.entry("source-tool", source: "ssh://git@example.com/tools/example-repo.git?foo=bar") }
        .to raise_error(RuntimeError, /should select a branch, tag or rev/)
    end

    it "rejects an scp-style git remote that cargo cannot parse as a URL" do
      expect { described_class.entry("example-tool", source: "git@example.com:tools/example-tool.git") }
        .to raise_error(RuntimeError, /should be a git URL/)
    end

    it "rejects unknown options" do
      expect { described_class.entry("third-tool", features: ["example-feature"]) }
        .to raise_error(RuntimeError, /unknown options/)
    end
  end

  describe "checking" do
    subject(:checker) { described_class.new }

    describe "#installed_and_up_to_date?" do
      it "passes the source through when checking a crate installed from a source" do
        expect(described_class).to receive(:package_installed?)
          .with("source-tool", source: "ssh://git@example.com/tools/example-repo.git")
          .and_return(true)

        expect(
          checker.installed_and_up_to_date?(
            { name: "source-tool", options: { source: "ssh://git@example.com/tools/example-repo.git" } },
          ),
        ).to be(true)
      end

      it "passes a nil source through for a registry crate" do
        expect(described_class).to receive(:package_installed?)
          .with("third-tool", source: nil)
          .and_return(true)

        expect(checker.installed_and_up_to_date?({ name: "third-tool", options: {} })).to be(true)
      end
    end

    describe "#find_actionable" do
      let(:entries) do
        [
          Homebrew::Bundle::Dsl::Entry.new(:cargo, "third-tool"),
          Homebrew::Bundle::Dsl::Entry.new(:cargo, "source-tool",
                                           source: "ssh://git@example.com/tools/example-repo.git"),
          Homebrew::Bundle::Dsl::Entry.new(:brew, "example-formula"),
        ]
      end

      it "returns missing cargo packages" do
        allow(described_class).to receive(:package_installed?) do |name, **|
          name == "third-tool"
        end

        actionable = checker.find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        expect(actionable).to eq(["Cargo Package source-tool needs to be installed."])
      end
    end
  end

  describe "dumping" do
    subject(:dumper) { described_class }

    context "when cargo is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      specify do
        expect(dumper.packages).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "when cargo is installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("cargo"))
      end

      it "returns package list" do
        expect(described_class).to receive(:command_output)
          .with(Pathname("cargo"), args: ["install", "--list"], print_stderr: true) do
          expect(ENV.fetch("CARGO_HOME", nil)).to eq("~/.cargo")
          expect(ENV.fetch("CARGO_INSTALL_ROOT", nil)).to eq("~/.cargo/bin")
          expect(ENV.fetch("RUSTUP_HOME", nil)).to eq("~/.rustup")
          <<~EOS
            third-tool v13.0.0:
                example-command
            example-tool v0.24.0 (https://example.com/tools/example-tool#3492d620)
          EOS
        end

        expect(dumper.packages).to eql([
          { name: "third-tool", source: nil },
          { name: "example-tool", source: "https://example.com/tools/example-tool" },
        ])
      end

      test_each_hash({
        "a git source with a resolved revision" => {
          origin: "ssh://git@example.com/tool.git#3492d620",
          source: "ssh://git@example.com/tool.git",
          dump:   'cargo "example-tool", source: "ssh://git@example.com/tool.git"',
        },
        "an HTTPS git source"                   => {
          origin: "https://github.com/example/tool#9f0e88bc",
          source: "https://github.com/example/tool",
          dump:   'cargo "example-tool", source: "https://github.com/example/tool"',
        },
        "a tag selector and resolved revision"  => {
          origin: "ssh://git@example.com/tool.git?tag=v4.0.0#3492d620",
          source: "ssh://git@example.com/tool.git?tag=v4.0.0",
          dump:   'cargo "example-tool", source: "ssh://git@example.com/tool.git?tag=v4.0.0"',
        },
        "a local installation path"             => {
          origin: "/Users/test/src/tool",
          source: nil,
          dump:   'cargo "example-tool"',
        },
        "a file:// repository"                  => {
          origin: "file:///Users/test/src/tool#3492d620",
          source: nil,
          dump:   'cargo "example-tool"',
        },
        "an unrecognised origin"                => {
          origin: "registry+sparse",
          source: nil,
          dump:   'cargo "example-tool"',
        },
      }) do |description, fixture|
        context "with #{description}" do
          before do
            stub_cargo_list("example-tool v1.0.0 (#{fixture.fetch(:origin)}):\n    example-tool\n")
          end

          it "parses and dumps the package source" do
            expect(packages: dumper.packages, dump: dumper.dump).to eq(
              packages: [{ name: "example-tool", source: fixture.fetch(:source) }],
              dump:     fixture.fetch(:dump),
            )
          end
        end
      end

      it "passes metacharacters in cargo's path literally" do
        cargo = Pathname("cargo; touch /tmp/pwned")
        allow(described_class).to receive(:package_manager_executable).and_return(cargo)
        expect(described_class).to receive(:command_output).with(cargo, args:         ["install", "--list"],
                                                                        print_stderr: true).and_return("")

        dumper.packages
      end

      it "dumps package list" do
        allow(dumper).to receive(:packages).and_return([
          { name: "third-tool", source: nil },
          { name: "example-tool", source: nil },
        ])
        expect(dumper.dump).to eql("cargo \"third-tool\"\ncargo \"example-tool\"")
      end
    end
  end

  describe "installing" do
    context "when Cargo is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "tries to install rust" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "rust", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("third-tool") }.to raise_error(RuntimeError)
      end
    end

    context "when Cargo is installed" do
      before do
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("cargo"))
      end

      context "when package is installed" do
        before do
          allow(described_class).to receive(:installed_packages)
            .and_return([{ name: "third-tool", source: nil }])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("third-tool")).to be(false)
        end

        it "does not treat a differently-sourced package as installed" do
          expect(
            described_class.package_installed?("third-tool", source: "https://example.com/tools/third-tool"),
          ).to be(false)
        end
      end

      context "when package is installed from a source" do
        before do
          allow(described_class).to receive(:installed_packages)
            .and_return([{ name: "source-tool", source: "ssh://git@example.com/tools/example-repo.git" }])
        end

        it "treats a matching source as installed" do
          expect(
            described_class.package_installed?("source-tool", source: "ssh://git@example.com/tools/example-repo.git"),
          ).to be(true)
        end

        it "does not treat a different source as installed" do
          expect(
            described_class.package_installed?("source-tool", source: "ssh://git@example.com/tools/example-tool.git"),
          ).to be(false)
        end

        it "does not treat the registry crate of the same name as installed" do
          expect(described_class.package_installed?("source-tool")).to be(false)
        end
      end

      context "when package is not installed" do
        before do
          allow(described_class).to receive_messages(
            package_manager_executable: Pathname.new("/tmp/rust/bin/cargo"), packages: [], installed_packages: [],
          )
        end

        it "installs package" do
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            expect(ENV.fetch("CARGO_HOME", nil)).to eq("~/.cargo")
            expect(ENV.fetch("CARGO_INSTALL_ROOT", nil)).to eq("~/.cargo/bin")
            expect(ENV.fetch("RUSTUP_HOME", nil)).to eq("~/.rustup")
            expect(ENV.fetch("PATH", "")).to start_with("/tmp/rust/bin:")
            expect(args).to eq(["/tmp/rust/bin/cargo", "install", "--locked", "third-tool"])
            expect(verbose).to be(false)
            true
          end
          expect(described_class.preinstall!("third-tool")).to be(true)
          expect(described_class.install!("third-tool")).to be(true)
        end

        it "installs multiple registry crates in one native batch" do
          entries = [
            Homebrew::Bundle::Dsl::Entry.new(:cargo, "third-tool"),
            Homebrew::Bundle::Dsl::Entry.new(:cargo, "example-tool"),
          ]
          expect(described_class.batch_installable?("third-tool")).to be(true)
          expect(Homebrew::Bundle).to receive(:system)
            .with("/tmp/rust/bin/cargo", "install", "--locked", "third-tool", "example-tool", verbose: false)
            .and_return(true)

          expect(described_class.install_batch!(entries, verbose: false)).to be(true)
        end

        it "installs a package from a git source by package name" do
          source = "ssh://git@example.com/tools/example-repo.git"
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            expect(args).to eq(["/tmp/rust/bin/cargo", "install", "--locked", "--git", source, "source-tool"])
            expect(verbose).to be(false)
            true
          end
          expect(described_class.preinstall!("source-tool", source:)).to be(true)
          expect(described_class.install!("source-tool", source:)).to be(true)
        end

        it "installs a package from a git branch" do
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            _ = verbose
            expect(args).to eq(["/tmp/rust/bin/cargo", "install", "--locked", "--git",
                                "ssh://git@example.com/tools/example-repo.git", "--branch", "next", "source-tool"])
            true
          end
          expect(
            described_class.install!("source-tool",
                                     source: "ssh://git@example.com/tools/example-repo.git?branch=next"),
          ).to be(true)
        end

        it "installs a package from a pinned git revision" do
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            _ = verbose
            expect(args).to eq(["/tmp/rust/bin/cargo", "install", "--locked", "--git",
                                "ssh://git@example.com/tools/example-repo.git", "--rev", "3492d620", "source-tool"])
            true
          end
          expect(
            described_class.install!("source-tool",
                                     source: "ssh://git@example.com/tools/example-repo.git?rev=3492d620"),
          ).to be(true)
        end

        it "updates dump output after install in the same process" do
          source = "ssh://git@example.com/tools/example-repo.git"
          allow(Homebrew::Bundle).to receive(:system).and_return(true)

          described_class.install!("source-tool", source:)

          expect(described_class.dump).to eql(%Q(cargo "source-tool", source: "#{source}"))
        end
      end
    end
  end

  describe "cleanup" do
    before do
      described_class.reset!
      crates = [
        { name: "third-tool", source: nil },
        { name: "other-tool", source: nil },
        { name: "example-tool", source: nil },
      ]
      allow(described_class).to receive_messages(
        package_manager_executable: Pathname.new("/tmp/rust/bin/cargo"),
        packages:                   crates,
        installed_packages:         crates,
      )
    end

    it "returns packages not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:cargo, "third-tool")]
      expect(described_class.cleanup_items(entries)).to eql(%w[other-tool example-tool])
    end

    it "returns the uninstall command result" do
      allow(Homebrew::Bundle).to receive(:system)
        .with("/tmp/rust/bin/cargo", "uninstall", "example", verbose: false).and_return(false)

      expect(
        described_class.uninstall_package!("example", executable: Pathname("/tmp/rust/bin/cargo")),
      ).to be(false)
    end

    it "returns frozen empty array when cargo is not installed" do
      allow(described_class).to receive(:package_manager_installed?).and_return(false)
      entries = [Homebrew::Bundle::Dsl::Entry.new(:cargo, "third-tool")]
      expect(described_class.cleanup_items(entries)).to eql([])
    end
  end
end
