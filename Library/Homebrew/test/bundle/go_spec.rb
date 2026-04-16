# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/go"

RSpec.describe Homebrew::Bundle::Go do
  describe "dumping" do
    subject(:dumper) { described_class }

    context "when go is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "returns an empty list" do
        expect(dumper.packages).to be_empty
      end

      it "dumps an empty string" do # rubocop:todo RSpec/AggregateExamples
        expect(dumper.dump).to eql("")
      end
    end

    context "when go is installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("go"))
      end

      it "returns package list" do
        allow(described_class).to receive(:`).with("go env GOBIN").and_return("")
        allow(described_class).to receive(:`).with("go env GOPATH").and_return("/Users/test/go")
        allow(File).to receive(:directory?).with("/Users/test/go/bin").and_return(true)
        allow(Dir).to receive(:glob).with("/Users/test/go/bin/*").and_return(["/Users/test/go/bin/crush"])
        allow(File).to receive(:executable?).with("/Users/test/go/bin/crush").and_return(true)
        allow(File).to receive(:directory?).with("/Users/test/go/bin/crush").and_return(false)
        allow(described_class).to receive(:`).with("go version -m \"/Users/test/go/bin/crush\" 2>/dev/null")
                                             .and_return("\tpath\tgithub.com/charmbracelet/crush\n")
        expect(dumper.packages).to eql(["github.com/charmbracelet/crush"])
      end

      it "dumps package list" do
        allow(dumper).to receive(:packages).and_return(["github.com/charmbracelet/crush"])
        expect(dumper.dump).to eql('go "github.com/charmbracelet/crush"')
      end
    end
  end

  describe "installing" do
    context "when Go is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "tries to install go" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "go", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("github.com/charmbracelet/crush") }.to raise_error(RuntimeError)
      end

      it "preserves upgrade_formulae while bootstrapping Go" do
        Homebrew::Bundle.upgrade_formulae = "foo,bar"

        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "go", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("github.com/charmbracelet/crush") }.to raise_error(RuntimeError)
        expect(Homebrew::Bundle.upgrade_formulae).to eql(["foo", "bar"])
      end
    end

    context "when Go is installed" do
      before do
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("go"))
      end

      context "when package is installed" do
        before do
          allow(described_class).to receive(:installed_packages)
            .and_return(["github.com/charmbracelet/crush"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("github.com/charmbracelet/crush")).to be(false)
        end
      end

      context "when package is not installed" do
        before do
          allow(described_class).to receive_messages(packages: [], installed_packages: [])
        end

        it "installs package" do
          expect(Homebrew::Bundle).to \
            receive(:system).with("go", "install", "github.com/charmbracelet/crush@latest", verbose: false)
                            .and_return(true)
          expect(described_class.preinstall!("github.com/charmbracelet/crush")).to be(true)
          expect(described_class.install!("github.com/charmbracelet/crush")).to be(true)
        end

        it "updates dump output after install in the same process" do
          expect(Homebrew::Bundle).to \
            receive(:system).with("go", "install", "github.com/charmbracelet/crush@latest", verbose: false)
                            .and_return(true)

          described_class.install!("github.com/charmbracelet/crush")

          expect(described_class.dump).to eql('go "github.com/charmbracelet/crush"')
        end
      end
    end
  end

  describe "cleanup" do
    before do
      described_class.reset!
      pkgs = %w[github.com/charmbracelet/crush github.com/golangci/golangci-lint/v2/cmd/golangci-lint]
      allow(described_class).to receive_messages(
        package_manager_executable: Pathname.new("go"),
        packages:                   pkgs,
        installed_packages:         pkgs,
      )
    end

    it "returns packages not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:go, "github.com/charmbracelet/crush")]
      expect(described_class.cleanup_items(entries))
        .to eql(%w[github.com/golangci/golangci-lint/v2/cmd/golangci-lint])
    end

    it "returns frozen empty array when go is not installed" do
      allow(described_class).to receive(:package_manager_installed?).and_return(false)
      entries = [Homebrew::Bundle::Dsl::Entry.new(:go, "github.com/charmbracelet/crush")]
      expect(described_class.cleanup_items(entries)).to eql([])
    end
  end
end
