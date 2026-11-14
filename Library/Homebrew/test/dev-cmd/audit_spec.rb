# typed: true
# frozen_string_literal: true

require "dev-cmd/audit"
require "cask/auditor"
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

    let(:tap_path) { Tap.fetch("homebrew/test-audit").path }
    let(:macos_only_cask_file) { tap_path/"Casks/macos-only-example.rb" }
    let(:linux_cask_file) { tap_path/"Casks/linux-example.rb" }
    let(:linux_only_cask_file) { tap_path/"Casks/linux-only-example.rb" }
    let(:tap) do
      instance_double(Tap, formula_files: [], cask_files: [macos_only_cask_file, linux_cask_file,
                                                           linux_only_cask_file])
    end

    after { FileUtils.rm_rf tap_path }

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
          zap :not_required
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
          zap :not_required
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
          zap :not_required
        end
      RUBY

      allow(Utils::GemSetup).to receive(:install_bundler_gems!)
      ENV.activate_extensions!
      allow(ENV).to receive(:setup_build_environment)
      allow(Tap).to receive(:fetch).and_call_original
      allow(Tap).to receive(:fetch).with("homebrew/test").and_return(tap)
      allow(Tap).to receive(:installed).and_return([])
    end

    it "audits a Linux-only cask on its supported platform" do
      cask = Homebrew::SimulateSystem.with(os: :linux, arch: :arm) do
        Cask::CaskLoader.from_path(linux_only_cask_file)
      end
      audited_systems = []
      allow(Cask::Auditor).to receive(:audit) do
        audited_systems << [Homebrew::SimulateSystem.current_os, Homebrew::SimulateSystem.current_arch]
        []
      end

      audit.audit_cask(cask, [[:macos, :arm]], no_named_args: true)

      expect(audited_systems).to eq([[:linux, :arm]])
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

    it "audits macOS-only casks under macOS when auditing all operating systems" do
      macos_url_cask_file = tap_path/"Casks/macos-url-example.rb"
      macos_url_cask_file.write <<~RUBY
        cask "macos-url-example" do
          version "1.0"
          sha256 "0000000000000000000000000000000000000000000000000000000000000000"

          on_macos do
            url "https://example.invalid/x-\#{version}.pkg"
          end

          name "Example"
          desc "macOS-only cask"
          homepage "https://example.invalid/"

          depends_on macos: :ventura

          binary "x"
          zap :not_required
        end
      RUBY
      allow(tap).to receive(:cask_files).and_return([macos_url_cask_file])

      expect { described_class.new(["--tap=homebrew/test", "--os=all", "--arch=arm"]).run }
        .not_to output.to_stdout
    end

    it "audits ARM-only casks under ARM when auditing Intel" do
      arm_url_cask_file = tap_path/"Casks/arm-url-example.rb"
      arm_url_cask_file.write <<~RUBY
        cask "arm-url-example" do
          version "1.0"
          sha256 "0000000000000000000000000000000000000000000000000000000000000000"

          on_arm do
            url "https://example.invalid/x-\#{version}.tar.gz"
          end

          name "Example"
          desc "ARM-only cask"
          homepage "https://example.invalid/"

          depends_on arch: :arm64

          binary "x"
          zap :not_required
        end
      RUBY
      allow(tap).to receive(:cask_files).and_return([arm_url_cask_file])

      Homebrew::SimulateSystem.with(os: :macos, arch: :intel) do
        expect { audit.run }.not_to output.to_stdout
      end
    end

    it "audits casks on the architecture each operating system supports" do
      os_arch_cask_file = tap_path/"Casks/os-arch-example.rb"
      os_arch_cask_file.write <<~RUBY
        cask "os-arch-example" do
          version "1.0"
          sha256 arm:          "0000000000000000000000000000000000000000000000000000000000000000",
                 x86_64_linux: "1111111111111111111111111111111111111111111111111111111111111111"

          url "https://example.invalid/x-\#{version}.tar.gz"
          name "Example"
          desc "macOS ARM and Linux Intel cask"
          homepage "https://example.invalid/"

          on_macos do
            depends_on arch: :arm64
          end

          on_linux do
            depends_on arch: :x86_64
          end

          binary "x"
          zap :not_required
        end
      RUBY
      allow(tap).to receive(:cask_files).and_return([os_arch_cask_file])

      expect { described_class.new(["--tap=homebrew/test", "--os=all", "--arch=intel"]).run }
        .not_to output.to_stdout
    end

    it "audits Linux Intel for a cask that only requires macOS on ARM" do
      arm_macos_cask_file = tap_path/"Casks/arm-macos-example.rb"
      arm_macos_cask_file.write <<~RUBY
        cask "arm-macos-example" do
          version "1.0"
          sha256 arm:         "0000000000000000000000000000000000000000000000000000000000000000",
                 intel:       "1111111111111111111111111111111111111111111111111111111111111111",
                 arm64_linux: "0000000000000000000000000000000000000000000000000000000000000000"

          url "https://example.invalid/x-\#{version}.tar.gz"
          name "Example"
          desc "Cask without a Linux Intel checksum"
          homepage "https://example.invalid/"

          on_arm do
            depends_on macos: :big_sur
          end

          binary "x"
          zap :not_required
        end
      RUBY
      allow(tap).to receive(:cask_files).and_return([arm_macos_cask_file])

      expect { described_class.new(["--tap=homebrew/test", "--os=all", "--arch=all"]).run }
        .to output(/a sha256 stanza is required/).to_stdout
    end

    it "audits an installed cask whose tap source has been removed" do
      path = Cask::Caskroom.path/"removed/.metadata/1.0/20200101000000.000/Casks/removed.rb"
      path.dirname.mkpath
      path.write <<~RUBY
        cask "removed" do
          version "1.0"
          sha256 :no_check
          url "https://example.com/removed-1.0.zip"
        end
      RUBY
      cask = Cask::CaskLoader.load_from_installed_caskfile(path)
      allow(Formula).to receive(:installed).and_return([])
      allow(Cask::Caskroom).to receive(:casks).and_return([cask])
      allow(Cask::Auditor).to receive(:audit).and_return([])

      expect { described_class.new(["--installed", "--skip-style", "--os=all", "--arch=all"]).run }.not_to raise_error
    end

    it "enumerates cask paths only once when auditing a tap across platforms" do
      real_tap = Tap.fetch("homebrew/test-audit")
      allow(Tap).to receive(:fetch).with("homebrew/test").and_return(real_tap)
      allow(Cask::Auditor).to receive(:audit).and_return([])
      expect(real_tap).to receive(:cask_files).once.and_call_original

      described_class.new(["--tap=homebrew/test", "--skip-style", "--os=all", "--arch=all"]).run
    end

    it "loads each cask file only once when auditing across platforms" do
      allow(tap).to receive(:cask_files).and_return([linux_cask_file])
      allow(Cask::Auditor).to receive(:audit).and_return([])
      expect(Cask::CaskLoader).to receive(:from_path).with(linux_cask_file).once.and_call_original

      described_class.new(["--tap=homebrew/test", "--os=all", "--arch=all"]).run
    end

    it "re-evaluates casks for each platform without exposing sensitive environment variables" do
      linux_cask_file.write <<~RUBY
        cask "linux-example" do
          on_macos do
            on_intel do
              version "1.0"
            end
            on_arm do
              version "2.0"
            end
          end
          on_linux do
            version "3.0"
          end
          url "https://example.invalid/\#{version}/\#{ENV["HOMEBREW_SECRET_TOKEN"] == "secret" ? "exposed" : "scrubbed"}.zip"
        end
      RUBY
      cask = Homebrew::SimulateSystem.with(os: :macos, arch: :intel) do
        Cask::CaskLoader.from_path(linux_cask_file)
      end
      stub_const("OnSystem::ALL_OS_OPTIONS", [:macos, :linux])
      command = described_class.new(["--cask", "--skip-style", "--os=all", "--arch=all", "linux-example"])
      allow(command.args.named).to receive(:to_formulae_and_casks_with_taps).and_return([cask])
      urls = []
      allow(Cask::Auditor).to receive(:audit) do |loaded_cask, **|
        urls << loaded_cask.url.to_s
        []
      end
      ENV["HOMEBREW_SECRET_TOKEN"] = "secret"

      command.run

      expect([urls, cask.url.to_s, ENV.fetch("HOMEBREW_SECRET_TOKEN")]).to eq([
        %w[https://example.invalid/1.0/scrubbed.zip https://example.invalid/2.0/scrubbed.zip
           https://example.invalid/3.0/scrubbed.zip https://example.invalid/3.0/scrubbed.zip],
        "https://example.invalid/1.0/scrubbed.zip",
        "secret",
      ])
    end

    it "reloads cask corrections before auditing the next platform" do
      allow(tap).to receive(:cask_files).and_return([linux_cask_file])
      versions = []
      allow(Cask::Auditor).to receive(:audit) do |cask, **|
        versions << cask.version.to_s
        linux_cask_file.atomic_write(linux_cask_file.read.sub('version "1.0"', 'version "2.0"'))
        []
      end

      described_class.new(["--tap=homebrew/test", "--fix", "--os=linux", "--arch=all"]).run

      expect(versions).to eq(["1.0", "2.0"])
    end

    it "audits an installed formula whose tap source has been removed" do
      path = HOMEBREW_CELLAR/"removed/1.0/.brew/removed.rb"
      path.dirname.mkpath
      path.write <<~RUBY
        class Removed < Formula
          url "https://example.com/removed-1.0.tar.gz"
        end
      RUBY
      allow(Formula).to receive(:installed).and_return([Formulary.from_path(path)])
      allow(Cask::Caskroom).to receive(:casks).and_return([])
      auditor = instance_double(Homebrew::FormulaAuditor, audit: nil, problems: [], new_formula_problems: [])
      allow(Homebrew::FormulaAuditor).to receive(:new).and_return(auditor)

      expect { described_class.new(["--installed", "--skip-style"]).run }.not_to raise_error
    end

    it "enumerates formula paths only once when auditing a tap across platforms" do
      real_tap = Tap.fetch("homebrew/test-audit")
      path = real_tap.path/"Formula/example.rb"
      path.dirname.mkpath
      path.write <<~RUBY
        class Example < Formula
          url "https://example.com/example-1.0.tar.gz"
        end
      RUBY
      allow(Tap).to receive(:fetch).with("homebrew/test").and_return(real_tap)
      auditor = instance_double(Homebrew::FormulaAuditor, audit: nil, problems: [], new_formula_problems: [])
      allow(Homebrew::FormulaAuditor).to receive(:new).and_return(auditor)
      allow(real_tap).to receive(:cask_files).and_return([])
      expect(real_tap).to receive(:formula_files).once.and_call_original

      described_class.new(["--tap=homebrew/test", "--skip-style", "--os=all", "--arch=all"]).run
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

    test_each_hash({
      []                                           => { only_cops: nil, except_cops: ["FormulaAuditStrict"] },
      ["--strict"]                                 => { only_cops: nil, except_cops: nil },
      ["--new", "--except-cops=FormulaAudit/Desc"] => { only_cops: nil, except_cops: nil },
      ["--except-cops=FormulaAudit/Desc"]          => { only_cops: nil, except_cops: ["FormulaAudit/Desc"] },
      ["--only-cops=FormulaAudit/Desc"]            => { only_cops: ["FormulaAudit/Desc"], except_cops: nil },
    }) do |flags, cops|
      it "checks style with #{cops} for #{flags}" do
        formula_file = tap_path/"Formula/example.rb"
        formula_file.dirname.mkpath
        formula_file.write <<~RUBY
          class Example < Formula
            url "https://example.com/example-1.0.tar.gz"
          end
        RUBY
        command = described_class.new([*flags, "example"])
        allow(command.args.named).to receive_messages(
          to_formulae_and_casks_with_taps: [Formulary.from_path(formula_file)],
          to_paths:                        [formula_file],
        )
        allow(Homebrew::FormulaAuditor).to receive(:new)
          .and_return(instance_double(Homebrew::FormulaAuditor, audit: nil, problems: [], new_formula_problems: []))

        expect(Homebrew::Style).to receive(:check_style_json)
          .with([formula_file], hash_including(cops))
          .and_return(instance_double(Homebrew::Style::Offenses, for_path: []))

        command.run
      end
    end
  end
end
