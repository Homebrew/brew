# typed: true
# frozen_string_literal: true

require "dev-cmd/audit"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::DevCmd::Audit do
  it_behaves_like "parseable arguments"

  it "audits a Formula and Cask", :cask, :integration_test do
    setup_test_formula "testball"

    expect { brew "audit", "--skip-style", "--only=description", "testball", "local-caffeine" }
      .to be_a_success
  end

  describe "#run" do
    subject(:audit) { described_class.new(["--tap=homebrew/test"]) }

    let(:tap_path) { mktmpdir }
    let(:macos_only_cask_file) { tap_path/"Casks/macos-only-example.rb" }
    let(:linux_cask_file) { tap_path/"Casks/linux-example.rb" }
    let(:linux_only_cask_file) { tap_path/"Casks/linux-only-example.rb" }
    let(:tap) do
      instance_double(Tap, formula_files: [], cask_files: [macos_only_cask_file, linux_cask_file,
                                                           linux_only_cask_file])
    end

    before do
      macos_only_cask_file.dirname.mkpath
      macos_only_cask_file.write <<~RUBY
        cask "macos-only-example" do
          version "1.0"
          sha256 arm:   "0000000000000000000000000000000000000000000000000000000000000000",
                 intel: "1111111111111111111111111111111111111111111111111111111111111111"
          url "https://example.invalid/x-\#{version}.pkg"
          name "Example"
          desc "macOS-only cask"
          homepage "https://example.invalid/"
          depends_on macos: :ventura
          binary "x"
        end
      RUBY
      linux_cask_file.write <<~RUBY
        cask "linux-example" do
          version "1.0"
          sha256 arm:   "0000000000000000000000000000000000000000000000000000000000000000",
                 intel: "1111111111111111111111111111111111111111111111111111111111111111"
          url "https://example.invalid/x-\#{version}.tar.gz"
          name "Example"
          desc "Linux-supported cask"
          homepage "https://example.invalid/"
          binary "x"
        end
      RUBY
      linux_only_cask_file.write <<~RUBY
        cask "linux-only-example" do
          version "1.0"
          sha256 arm64_linux:  "0000000000000000000000000000000000000000000000000000000000000000",
                 x86_64_linux: "1111111111111111111111111111111111111111111111111111111111111111"
          url "https://example.invalid/x-\#{version}.tar.gz"
          name "Example"
          desc "Linux-only cask"
          homepage "https://example.invalid/"
          depends_on :linux
          binary "x"
        end
      RUBY

      allow(Utils::GemSetup).to receive(:install_bundler_gems!)
      ENV.activate_extensions!
      allow(ENV).to receive(:setup_build_environment)
      allow(Tap).to receive(:fetch).and_call_original
      allow(Tap).to receive(:fetch).with("homebrew/test").and_return(tap)
      allow(Tap).to receive(:installed).and_return([])
    end

    it "audits Linux-supporting casks and skips macOS-only ones on Linux" do
      problems = a_string_matching(
        /\A(?=.*linux-example)(?=.*a sha256 stanza is required)(?!.*macos-only-example).*\z/m,
      )

      Homebrew::SimulateSystem.with(os: :linux) do
        expect { audit.run }.to output(problems).to_stdout
                                                .and output(/1 problem in 1 cask detected/).to_stderr
      end
    end

    it "audits Linux-only casks under Linux when running on macOS" do
      Homebrew::SimulateSystem.with(os: :macos) do
        expect { audit.run }.not_to output.to_stdout
      end
    end

    it "enables API access when auditing external formulae after it was automatically disabled" do
      formula_file = tap_path/"Formula/example.rb"
      formula_file.dirname.mkpath
      formula_file.write <<~RUBY
        class Example < Formula
          desc "Example"
          homepage "https://example.com"
          url "https://example.com/example-1.0.tar.gz"
          sha256 "0000000000000000000000000000000000000000000000000000000000000000"

          depends_on "dependency"
        end
      RUBY
      allow(tap).to receive_messages(formula_files: [formula_file], cask_files: [])
      formula_auditor = instance_double(Homebrew::FormulaAuditor, audit: nil, problems: [], new_formula_problems: [])

      with_env(HOMEBREW_NO_INSTALL_FROM_API: "1", HOMEBREW_AUTOMATICALLY_SET_NO_INSTALL_FROM_API: "1") do
        expect(Homebrew::FormulaAuditor).to receive(:new) do
          expect(Homebrew::EnvConfig.no_install_from_api?).to be(false)
          formula_auditor
        end

        audit.run
      end
    end
  end
end
