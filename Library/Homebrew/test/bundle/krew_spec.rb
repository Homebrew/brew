# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/krew"

RSpec.describe Homebrew::Bundle::Krew do
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
                                                   package_manager_executable: Pathname.new("kubectl"))
      end

      it "returns plugin list" do
        allow(described_class).to receive(:`).and_return("ctx\nneat\nns\n")

        expect(dumper.packages).to eql(%w[ctx neat ns])
      end

      it "handles empty output" do
        allow(described_class).to receive(:`).and_return("")

        expect(dumper.packages).to be_empty
      end

      it "dumps plugin list" do
        allow(dumper).to receive(:packages).and_return(["ctx", "ns", "neat"])
        expect(dumper.dump).to eql("krew \"ctx\"\nkrew \"ns\"\nkrew \"neat\"")
      end
    end
  end

  describe "installing" do
    context "when kubectl is not found" do
      before do
        described_class.reset!
        allow(described_class).to receive_messages(package_manager_executable: nil, package_manager_installed?: false)
      end

      it "tries to install krew" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "krew", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("ctx") }.to raise_error(RuntimeError)
      end

      it "preserves upgrade_formulae while bootstrapping krew" do
        Homebrew::Bundle.upgrade_formulae = "foo,bar"

        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "krew", verbose: false)
                          .and_return(true)
        expect { described_class.preinstall!("ctx") }.to raise_error(RuntimeError)
        expect(Homebrew::Bundle.upgrade_formulae).to eql(["foo", "bar"])
      end
    end

    context "when kubectl and krew are installed" do
      before do
        allow(described_class).to receive_messages(
          package_manager_executable: Pathname.new("/usr/local/bin/kubectl"),
          package_manager_installed?: true,
        )
      end

      context "when plugin is installed" do
        before do
          allow(described_class).to receive(:installed_packages).and_return(["ctx"])
        end

        it "skips" do
          expect(Homebrew::Bundle).not_to receive(:system)
          expect(described_class.preinstall!("ctx")).to be(false)
        end
      end

      context "when plugin is not installed" do
        before do
          described_class.reset!
          allow(described_class).to receive_messages(
            package_manager_executable: Pathname.new("/usr/local/bin/kubectl"),
            package_manager_installed?: true,
            installed_packages:         [],
          )
        end

        it "installs plugin" do
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            expect(ENV.fetch("PATH", "")).to start_with("/usr/local/bin:")
            expect(args).to eq(["/usr/local/bin/kubectl", "krew", "install", "ctx"])
            expect(verbose).to be(false)
            true
          end
          expect(described_class.preinstall!("ctx")).to be(true)
          expect(described_class.install!("ctx")).to be(true)
        end

        it "updates dump output after install" do
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            expect(args).to eq(["/usr/local/bin/kubectl", "krew", "install", "ctx"])
            expect(verbose).to be(false)
            true
          end

          described_class.install!("ctx")

          expect(described_class.dump).to eql('krew "ctx"')
        end
      end
    end
  end
end
