# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/npm"
require "language/node"

RSpec.describe Homebrew::Bundle::Npm do
  let(:klass) { Homebrew::Bundle::Npm }

  describe "dumping" do
    subject(:dumper) { klass }

    context "when neither pnpm nor npm is installed" do
      before do
        klass.reset!
        allow(klass).to receive(:package_manager_executable).and_return(nil)
      end

      specify do
        expect(dumper.packages).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "when npm is installed" do
      before do
        klass.reset!
        allow(klass).to receive(:package_manager_executable).and_return(Pathname.new("npm"))
      end

      it "returns package list" do
        allow(klass).to receive(:`).with("npm list -g --depth=0 --json 2>/dev/null").and_return(<<~JSON)
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

        allow(klass).to receive(:package_manager_executable).and_return(npm)
        expect(klass).to receive(:`).with("#{npm} list -g --depth=0 --json 2>/dev/null") do
          expect(ENV.fetch("PATH", "")).to start_with("#{npm.dirname}:")
          '{"dependencies":{"eslint":{"version":"10.4.0"}}}'
        end

        expect(dumper.packages).to eql(["eslint"])
      end

      it "excludes npm itself from the package list" do
        allow(klass).to receive(:`).with("npm list -g --depth=0 --json 2>/dev/null").and_return(<<~JSON)
          {
            "dependencies": {
              "npm": { "version": "11.11.0" }
            }
          }
        JSON

        expect(dumper.packages).to be_empty
      end

      it "handles invalid JSON" do
        allow(klass).to receive(:`).with("npm list -g --depth=0 --json 2>/dev/null").and_return("not json")

        expect(dumper.packages).to be_empty
      end

      it "handles empty output" do
        allow(klass).to receive(:`).with("npm list -g --depth=0 --json 2>/dev/null").and_return("")

        expect(dumper.packages).to be_empty
      end

      it "dumps package list" do
        allow(dumper).to receive(:packages).and_return(["vercel", "typescript"])
        expect(dumper.dump).to eql("npm \"vercel\"\nnpm \"typescript\"")
      end
    end

    context "when pnpm is installed" do
      before do
        klass.reset!
        allow(klass).to receive(:package_manager_executable).and_return(Pathname.new("pnpm"))
      end

      it "returns package list" do
        allow(klass).to receive(:`).with("pnpm list -g --depth=0 --json 2>/dev/null").and_return(<<~JSON)
          [
            {
              "dependencies": {
                "pnpm": { "version": "10.23.0" },
                "vercel": { "version": "39.0.0" },
                "typescript": { "version": "5.7.3" }
              }
            }
          ]
        JSON

        expect(dumper.packages).to eql(%w[vercel typescript])
      end

      it "adds pnpm's directory to PATH when listing packages" do
        pnpm = mktmpdir/"bin/pnpm"
        pnpm.dirname.mkpath
        pnpm.write("")

        allow(klass).to receive(:package_manager_executable).and_return(pnpm)
        expect(klass).to receive(:`).with("#{pnpm} list -g --depth=0 --json 2>/dev/null") do
          expect(ENV.fetch("PATH", "")).to start_with("#{pnpm.dirname}:")
          '[{"dependencies":{"eslint":{"version":"10.4.0"}}}]'
        end

        expect(dumper.packages).to eql(["eslint"])
      end

      it "excludes pnpm itself from the package list" do
        allow(klass).to receive(:`).with("pnpm list -g --depth=0 --json 2>/dev/null").and_return(<<~JSON)
          [
            {
              "dependencies": {
                "pnpm": { "version": "10.23.0" }
              }
            }
          ]
        JSON

        expect(dumper.packages).to be_empty
      end

      it "dumps package list using npm entries" do
        allow(dumper).to receive(:packages).and_return(["vercel", "typescript"])
        expect(dumper.dump).to eql("npm \"vercel\"\nnpm \"typescript\"")
      end
    end

    context "when both pnpm and npm are installed" do
      before do
        klass.reset!
        allow(klass).to receive(:package_manager_executable).and_return(Pathname.new("pnpm"))
      end

      it "prefers pnpm" do
        allow(klass).to receive(:`).with("pnpm list -g --depth=0 --json 2>/dev/null").and_return(<<~JSON)
          [{"dependencies":{"eslint":{"version":"10.4.0"}}}]
        JSON

        expect(dumper.packages).to eql(["eslint"])
      end
    end
  end

  describe "cleanup" do
    before do
      klass.reset!
      allow(klass).to receive_messages(
        package_manager_executable: Pathname.new("/opt/homebrew/bin/npm"),
        packages:                   %w[vercel typescript prettier],
        installed_packages:         %w[vercel typescript prettier],
      )
    end

    it "returns packages not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:npm, "vercel")]
      expect(klass.cleanup_items(entries)).to eql(%w[typescript prettier])
    end

    it "returns empty when all packages are in Brewfile" do
      entries = [
        Homebrew::Bundle::Dsl::Entry.new(:npm, "vercel"),
        Homebrew::Bundle::Dsl::Entry.new(:npm, "typescript"),
        Homebrew::Bundle::Dsl::Entry.new(:npm, "prettier"),
      ]
      expect(klass.cleanup_items(entries)).to eql([])
    end

    it "returns frozen empty array when npm is not installed" do
      allow(klass).to receive(:package_manager_installed?).and_return(false)
      entries = [Homebrew::Bundle::Dsl::Entry.new(:npm, "vercel")]
      expect(klass.cleanup_items(entries)).to eql([])
    end
  end

  describe "installing" do
    context "when neither pnpm nor npm is installed" do
      before do
        klass.reset!
        allow(klass).to receive(:package_manager_executable).and_return(nil)
      end

      it "tries to install node and pnpm" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "node", "pnpm", verbose: false)
                          .and_return(true)
        expect { klass.preinstall!("vercel") }.to raise_error(RuntimeError)
      end
    end

    context "when npm is installed" do
      before do
        allow(klass).to receive(:package_manager_executable).and_return(Pathname.new("npm"))
      end

      context "when package is installed" do
        before do
          allow(klass).to receive(:installed_packages)
            .and_return(["vercel"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(klass.preinstall!("vercel")).to be(false)
        end
      end

      context "when package is not installed" do
        before do
          allow(klass).to receive_messages(
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
          expect(klass.preinstall!("vercel")).to be(true)
          expect(klass.install!("vercel")).to be(true)
        end
      end
    end

    context "when pnpm is installed" do
      before do
        allow(klass).to receive(:package_manager_executable).and_return(Pathname.new("pnpm"))
      end

      context "when package is installed" do
        before do
          allow(klass).to receive(:installed_packages)
            .and_return(["vercel"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(klass.preinstall!("vercel")).to be(false)
        end
      end

      context "when package is not installed" do
        before do
          allow(klass).to receive_messages(
            package_manager_executable: Pathname.new("/opt/homebrew/bin/pnpm"),
            installed_packages:         [],
          )
        end

        it "installs package" do
          expect(Homebrew::Bundle).to receive(:system)
            .with(
              "/opt/homebrew/bin/pnpm",
              "add",
              "-g",
              "vercel",
              verbose: false,
            )
            .and_return(true)
          expect(klass.preinstall!("vercel")).to be(true)
          expect(klass.install!("vercel")).to be(true)
        end
      end
    end
  end
end
