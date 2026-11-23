# typed: strict
# frozen_string_literal: true

require "test_bot"
require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot::Casks do
  it "records a failed cask install, cleans up newly installed dependencies and continues", :cask do
    tap = CoreCaskTap.instance
    casks = described_class.new(tap:, git: "git", dry_run: false, fail_fast: false, verbose: false)
    allow(Cask::Caskroom).to receive(:tokens).and_return(%w[local-caffeine], %w[local-caffeine])
    allow(Cask::Caskroom).to receive(:cask_installed?).with("local-caffeine").and_return(false, true)
    (HOMEBREW_CELLAR/"preexisting/1.0").mkpath
    allow(SystemCommand).to receive(:run).and_call_original
    %w[install uninstall].each do |operation|
      allow(SystemCommand).to receive(:run).with(
        HOMEBREW_BREW_FILE.to_s, hash_including(args: [operation, "--cask", "--", "local-caffeine"])
      ) do |_, **options|
        if operation == "install"
          raise "Install cleanup must be disabled" if options.fetch(:env)["HOMEBREW_NO_INSTALL_CLEANUP"] != "1"

          (HOMEBREW_CELLAR/"new-dependency/1.0").mkpath
        end
        instance_double(SystemCommand::Result, success?: operation == "uninstall", merged_output: +"")
      end
    end
    allow(SystemCommand).to receive(:run).with(
      HOMEBREW_BREW_FILE.to_s, hash_including(args: %w[uninstall --formula -- new-dependency])
    ).and_return(instance_double(SystemCommand::Result, success?: true, merged_output: +""))
    allow(SystemCommand).to receive(:run).with(
      HOMEBREW_BREW_FILE.to_s, hash_including(args: %w[install --cask -- local-transmission-zip])
    ).and_return(instance_double(SystemCommand::Result, success?: true, merged_output: +""))

    casks.run!(["Casks/local-caffeine.rb", "Casks/local-transmission-zip.rb"])

    expect(casks.steps.map { |step| [step.command.drop(1), step.failed?] }).to eq([
      [%w[install --cask -- local-caffeine], true],
      [%w[uninstall --cask -- local-caffeine], false],
      [%w[uninstall --formula -- new-dependency], false],
      [%w[install --cask -- local-transmission-zip], false],
    ])
  ensure
    FileUtils.rm_rf([HOMEBREW_CELLAR/"preexisting", HOMEBREW_CELLAR/"new-dependency"])
  end

  it "records a failure for a supported cask without a URL", :cask do
    tap = CoreCaskTap.instance
    path = tap.cask_dir/"local-caffeine.rb"
    cask = Cask::CaskLoader.from_tap_path(path)
    allow(cask).to receive(:url).and_return(nil)
    allow(Cask::CaskLoader).to receive(:from_tap_path).with(path).and_return(cask)
    allow(SystemCommand).to receive(:run).with(
      HOMEBREW_BREW_FILE.to_s, hash_including(args: %w[audit --cask --only=required_stanzas -- local-caffeine])
    ).and_return(instance_double(SystemCommand::Result, success?: false, merged_output: +"a url stanza is required"))
    casks = described_class.new(tap:, git: "git", dry_run: false, fail_fast: false, verbose: false)

    casks.run!(["Casks/local-caffeine.rb"])

    expect(casks.failed_steps.map(&:name)).to eq(["audit"])
  end

  it "skips ARM-only casks on Intel before evaluating their source", :cask do
    tap = CoreCaskTap.instance
    path = tap.cask_dir/"arm-only-test.rb"
    path.write <<~'RUBY'
      cask "arm-only-test" do
        depends_on arch: [:arm64]
        on_arm do
          version "1.2.3"
        end
        url "https://example.test/#{version.major_minor}.zip"
      end
    RUBY
    casks = described_class.new(tap:, dry_run: true)

    Homebrew::SimulateSystem.with(arch: :intel) do
      expect { casks.run!(["Casks/arm-only-test.rb"]) }
        .to output("Skipping arm-only-test: unsupported on this runner.\n").to_stdout
    end
  ensure
    path.unlink if path&.exist?
  end

  it "skips macOS-only casks on Linux before evaluating their source", :cask do
    tap = CoreCaskTap.instance
    path = tap.cask_dir/"macos-only-test.rb"
    path.write <<~'RUBY'
      cask "macos-only-test" do
        depends_on maximum_macos: :sequoia
        on_macos do
          version "1.2.3"
        end
        url "https://example.test/#{version.major_minor}.zip"
      end
    RUBY
    casks = described_class.new(tap:, git: "git", dry_run: true, fail_fast: false, verbose: false)

    Homebrew::SimulateSystem.with(os: :linux) do
      expect { casks.run!(["Casks/macos-only-test.rb"]) }
        .to output("Skipping macos-only-test: unsupported on this runner.\n").to_stdout
    end
  ensure
    path.unlink if path&.exist?
  end
end
