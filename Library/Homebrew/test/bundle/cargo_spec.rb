# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/cargo"

RSpec.describe Homebrew::Bundle::Cargo do
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

  describe "entries" do
    it "accepts a source option" do
      entry = described_class.entry("tftio-kb", source: "ssh://git@example.com/tftio/kb.git")
      expect(entry.name).to eql("tftio-kb")
      expect(entry.options).to eql({ source: "ssh://git@example.com/tftio/kb.git" })
    end

    it "accepts a source that selects a git reference" do
      entry = described_class.entry("tftio-kb", source: "ssh://git@example.com/tftio/kb.git?branch=next")
      expect(entry.options).to eql({ source: "ssh://git@example.com/tftio/kb.git?branch=next" })
    end

    it "stores no options when no source is given" do
      expect(described_class.entry("ripgrep").options).to be_empty
    end

    it "rejects a non-String source" do
      expect { described_class.entry("tftio-kb", source: ["ssh://git@example.com/tftio/kb.git"]) }
        .to raise_error(RuntimeError, /options\[:source\]/)
    end

    it "rejects a source that is not a git URL" do
      expect { described_class.entry("tftio-kb", source: "tftio-kb") }
        .to raise_error(RuntimeError, /should be a git URL/)
    end

    it "rejects a local path, which does not resolve on another machine" do
      expect { described_class.entry("bat", source: "/Users/test/src/bat") }
        .to raise_error(RuntimeError, /should be a git URL/)
    end

    it "rejects a file:// git URL, which does not resolve on another machine either" do
      expect { described_class.entry("bat", source: "file:///Users/test/src/bat") }
        .to raise_error(RuntimeError, /should be a git URL/)
    end

    it "rejects a git query that selects something other than a branch, tag or rev" do
      expect { described_class.entry("tftio-kb", source: "ssh://git@example.com/tftio/kb.git?foo=bar") }
        .to raise_error(RuntimeError, /should select a branch, tag or rev/)
    end

    it "rejects an scp-style git remote that cargo cannot parse as a URL" do
      expect { described_class.entry("bat", source: "git@github.com:sharkdp/bat.git") }
        .to raise_error(RuntimeError, /should be a git URL/)
    end

    it "rejects unknown options" do
      expect { described_class.entry("ripgrep", features: ["pcre2"]) }
        .to raise_error(RuntimeError, /unknown options/)
    end
  end

  describe "checking" do
    subject(:checker) { described_class.new }

    describe "#installed_and_up_to_date?" do
      it "passes the source through when checking a crate installed from a source" do
        expect(described_class).to receive(:package_installed?)
          .with("tftio-kb", source: "ssh://git@example.com/tftio/kb.git")
          .and_return(true)

        expect(
          checker.installed_and_up_to_date?(
            { name: "tftio-kb", options: { source: "ssh://git@example.com/tftio/kb.git" } },
          ),
        ).to be(true)
      end

      it "passes a nil source through for a registry crate" do
        expect(described_class).to receive(:package_installed?)
          .with("ripgrep", source: nil)
          .and_return(true)

        expect(checker.installed_and_up_to_date?({ name: "ripgrep", options: {} })).to be(true)
      end
    end

    describe "#find_actionable" do
      let(:entries) do
        [
          Homebrew::Bundle::Dsl::Entry.new(:cargo, "ripgrep"),
          Homebrew::Bundle::Dsl::Entry.new(:cargo, "tftio-kb", source: "ssh://git@example.com/tftio/kb.git"),
          Homebrew::Bundle::Dsl::Entry.new(:brew, "wget"),
        ]
      end

      it "returns missing cargo packages" do
        allow(described_class).to receive(:package_installed?) do |name, **|
          name == "ripgrep"
        end

        actionable = checker.find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        expect(actionable).to eq(["Cargo Package tftio-kb needs to be installed."])
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
        expect(described_class).to receive(:`).with("cargo install --list") do
          expect(ENV.fetch("CARGO_HOME", nil)).to eq("~/.cargo")
          expect(ENV.fetch("CARGO_INSTALL_ROOT", nil)).to eq("~/.cargo/bin")
          expect(ENV.fetch("RUSTUP_HOME", nil)).to eq("~/.rustup")
          <<~EOS
            ripgrep v13.0.0:
                rg
            bat v0.24.0 (https://github.com/sharkdp/bat#3492d620)
          EOS
        end

        expect(dumper.packages).to eql([
          { name: "ripgrep", source: nil },
          { name: "bat", source: "https://github.com/sharkdp/bat" },
        ])
      end

      it "parses a git source and strips the resolved revision" do
        allow(described_class).to receive(:`).with("cargo install --list").and_return(<<~EOS)
          tftio-kb v4.0.0 (ssh://git@example.com/tftio/kb.git#3492d620):
              kb
        EOS

        expect(dumper.packages).to eql([
          { name: "tftio-kb", source: "ssh://git@example.com/tftio/kb.git" },
        ])
        expect(dumper.dump).to eql('cargo "tftio-kb", source: "ssh://git@example.com/tftio/kb.git"')
      end

      it "parses an https git source" do
        allow(described_class).to receive(:`).with("cargo install --list").and_return(<<~EOS)
          ripgrep v13.0.0 (https://github.com/BurntSushi/ripgrep#9f0e88bc):
              rg
        EOS

        expect(dumper.packages.first&.dig(:source)).to eql("https://github.com/BurntSushi/ripgrep")
      end

      it "keeps a tag selector while stripping the resolved revision" do
        allow(described_class).to receive(:`).with("cargo install --list").and_return(<<~EOS)
          tftio-kb v4.0.0 (ssh://git@example.com/tftio/kb.git?tag=v4.0.0#3492d620):
              kb
        EOS

        expect(dumper.dump).to eql('cargo "tftio-kb", source: "ssh://git@example.com/tftio/kb.git?tag=v4.0.0"')
      end

      it "dumps a crate installed from a local path without a source" do
        allow(described_class).to receive(:`).with("cargo install --list").and_return(<<~EOS)
          bat v0.24.0 (/Users/test/src/bat):
              bat
        EOS

        expect(dumper.dump).to eql('cargo "bat"')
      end

      it "dumps a crate installed from a file:// repository without a source" do
        allow(described_class).to receive(:`).with("cargo install --list").and_return(<<~EOS)
          bat v0.24.0 (file:///Users/test/src/bat#3492d620):
              bat
        EOS

        expect(dumper.dump).to eql('cargo "bat"')
      end

      it "ignores an origin it cannot classify as a source" do
        allow(described_class).to receive(:`).with("cargo install --list").and_return(<<~EOS)
          ripgrep v13.0.0 (registry+sparse):
              rg
        EOS

        expect(dumper.packages.first&.dig(:source)).to be_nil
        expect(dumper.dump).to eql('cargo "ripgrep"')
      end

      it "dumps package list" do
        allow(dumper).to receive(:packages).and_return([
          { name: "ripgrep", source: nil },
          { name: "bat", source: nil },
        ])
        expect(dumper.dump).to eql("cargo \"ripgrep\"\ncargo \"bat\"")
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
        expect { described_class.preinstall!("ripgrep") }.to raise_error(RuntimeError)
      end
    end

    context "when Cargo is installed" do
      before do
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("cargo"))
      end

      context "when package is installed" do
        before do
          allow(described_class).to receive(:installed_packages)
            .and_return([{ name: "ripgrep", source: nil }])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("ripgrep")).to be(false)
        end

        it "does not treat a differently-sourced package as installed" do
          expect(
            described_class.package_installed?("ripgrep", source: "https://github.com/BurntSushi/ripgrep"),
          ).to be(false)
        end
      end

      context "when package is installed from a source" do
        before do
          allow(described_class).to receive(:installed_packages)
            .and_return([{ name: "tftio-kb", source: "ssh://git@example.com/tftio/kb.git" }])
        end

        it "treats a matching source as installed" do
          expect(
            described_class.package_installed?("tftio-kb", source: "ssh://git@example.com/tftio/kb.git"),
          ).to be(true)
        end

        it "does not treat a different source as installed" do
          expect(
            described_class.package_installed?("tftio-kb", source: "ssh://git@example.com/tftio/other.git"),
          ).to be(false)
        end

        it "does not treat the registry crate of the same name as installed" do
          expect(described_class.package_installed?("tftio-kb")).to be(false)
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
            expect(args).to eq(["/tmp/rust/bin/cargo", "install", "--locked", "ripgrep"])
            expect(verbose).to be(false)
            true
          end
          expect(described_class.preinstall!("ripgrep")).to be(true)
          expect(described_class.install!("ripgrep")).to be(true)
        end

        it "installs a package from a git source by package name" do
          source = "ssh://git@example.com/tftio/kb.git"
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            expect(args).to eq(["/tmp/rust/bin/cargo", "install", "--locked", "--git", source, "tftio-kb"])
            expect(verbose).to be(false)
            true
          end
          expect(described_class.preinstall!("tftio-kb", source:)).to be(true)
          expect(described_class.install!("tftio-kb", source:)).to be(true)
        end

        it "installs a package from a git branch" do
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            _ = verbose
            expect(args).to eq(["/tmp/rust/bin/cargo", "install", "--locked", "--git",
                                "ssh://git@example.com/tftio/kb.git", "--branch", "next", "tftio-kb"])
            true
          end
          expect(
            described_class.install!("tftio-kb", source: "ssh://git@example.com/tftio/kb.git?branch=next"),
          ).to be(true)
        end

        it "installs a package from a pinned git revision" do
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            _ = verbose
            expect(args).to eq(["/tmp/rust/bin/cargo", "install", "--locked", "--git",
                                "ssh://git@example.com/tftio/kb.git", "--rev", "3492d620", "tftio-kb"])
            true
          end
          expect(
            described_class.install!("tftio-kb", source: "ssh://git@example.com/tftio/kb.git?rev=3492d620"),
          ).to be(true)
        end

        it "updates dump output after install in the same process" do
          source = "ssh://git@example.com/tftio/kb.git"
          allow(Homebrew::Bundle).to receive(:system).and_return(true)

          described_class.install!("tftio-kb", source:)

          expect(described_class.dump).to eql(%Q(cargo "tftio-kb", source: "#{source}"))
        end
      end
    end
  end

  describe "cleanup" do
    before do
      described_class.reset!
      crates = [
        { name: "ripgrep", source: nil },
        { name: "fd-find", source: nil },
        { name: "bat", source: nil },
      ]
      allow(described_class).to receive_messages(
        package_manager_executable: Pathname.new("/tmp/rust/bin/cargo"),
        packages:                   crates,
        installed_packages:         crates,
      )
    end

    it "returns packages not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:cargo, "ripgrep")]
      expect(described_class.cleanup_items(entries)).to eql(%w[fd-find bat])
    end

    it "returns frozen empty array when cargo is not installed" do
      allow(described_class).to receive(:package_manager_installed?).and_return(false)
      entries = [Homebrew::Bundle::Dsl::Entry.new(:cargo, "ripgrep")]
      expect(described_class.cleanup_items(entries)).to eql([])
    end
  end
end
