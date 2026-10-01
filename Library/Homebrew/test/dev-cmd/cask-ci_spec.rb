# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/cask-ci"

RSpec.describe Homebrew::DevCmd::CaskCi do
  sig { returns(Cask::CI::Check::Snapshot) }
  let(:empty_snapshot) do
    {
      installed_apps:       [],
      installed_kexts:      [],
      installed_pkgs:       [],
      installed_launchjobs: [],
      loaded_launchjobs:    [],
    }
  end

  it_behaves_like "parseable arguments"

  it "requires a cask for info" do
    expect { described_class.new(["info"]).run }
      .to raise_error(UsageError, /The `info` operation requires a cask\./)
  end

  it "requires a cask for zap-check" do
    expect { described_class.new(["zap-check"]).run }
      .to raise_error(UsageError, /The `zap-check` operation requires a cask\./)
  end

  it "requires a cask for check" do
    expect { described_class.new(["check"]).run }
      .to raise_error(UsageError, /The `check` operation requires a cask\./)
  end

  it "rejects a cask for snapshot" do
    expect { described_class.new(["snapshot", "test-cask"]).run }
      .to raise_error(UsageError, /The `snapshot` operation does not accept a cask\./)
  end

  it "rejects unknown operations" do
    expect { described_class.new(["unknown"]).run }
      .to raise_error(UsageError, /Unknown cask CI operation: unknown/)
  end

  it "writes JSON-encoded cask information", :cask, :needs_macos do
    mktmpdir do |path|
      github_output = path/"github-output"
      ENV["GITHUB_OUTPUT"] = github_output.to_s
      ENV["GITHUB_ENV"] = (path/"github-env").to_s

      described_class.new(["info", cask_path("with-installer-manual").to_s]).run

      expect(github_output.read.lines(chomp: true)).to eq([
        "manual_installer=true",
        "macos_requirement_satisfied=true",
        "formula_dependencies=[]",
      ])
    end
  end

  it "omits empty environment values", :cask, :needs_macos do
    mktmpdir do |path|
      github_env = path/"github-env"
      ENV["GITHUB_OUTPUT"] = (path/"github-output").to_s
      ENV["GITHUB_ENV"] = github_env.to_s

      described_class.new(["info", cask_path("with-installer-manual").to_s]).run

      expect(github_env.read).to be_empty
    end
  end

  it "writes non-empty cask dependencies", :cask, :needs_macos do
    mktmpdir do |path|
      github_env = path/"github-env"
      ENV["GITHUB_OUTPUT"] = (path/"github-output").to_s
      ENV["GITHUB_ENV"] = github_env.to_s

      described_class.new(["info", cask_path("with-depends-on-cask-multiple").to_s]).run

      expect(github_env.read).to eq("CASK_DEPENDENCIES=local-caffeine local-transmission-zip\n")
    end
  end

  it "writes the prefixed system snapshot" do
    mktmpdir do |path|
      github_env = path/"github-env"
      command = described_class.new(["snapshot"])
      allow(command).to receive(:system_snapshot).and_return(empty_snapshot)
      ENV["GITHUB_ENV"] = github_env.to_s

      command.run

      expect(github_env.read).to eq("HOMEBREW_SNAPSHOT_BEFORE=#{JSON.generate(empty_snapshot)}\n")
    end
  end

  it "sets Homebrew.failed when check finds errors" do
    mktmpdir do |path|
      caskfile = path/"cask-ci-test.rb"
      caskfile.write <<~RUBY
        cask "cask-ci-test" do
          version "1.0"
          sha256 :no_check
          url "https://brew.sh/cask-ci-test-1.0.zip"
          app "Cask CI Test.app"
        end
      RUBY
      after = empty_snapshot.merge(installed_apps: ["/Applications/Cask CI Test.app"])
      command = described_class.new(["check", caskfile.to_s])
      allow(command).to receive(:system_snapshot).and_return(after)
      ENV["HOMEBREW_SNAPSHOT_BEFORE"] = JSON.generate(empty_snapshot)

      expect { command.run }
        .to change(Homebrew, :failed?).from(false).to(true)
        .and output(/::error.*Some applications are still installed/).to_stdout
    end
  end

  it "leaves Homebrew.failed clear when check finds no errors" do
    mktmpdir do |path|
      caskfile = path/"cask-ci-test.rb"
      caskfile.write <<~RUBY
        cask "cask-ci-test" do
          version "1.0"
          sha256 :no_check
          url "https://brew.sh/cask-ci-test-1.0.zip"
          app "Cask CI Test.app"
        end
      RUBY
      command = described_class.new(["check", caskfile.to_s])
      allow(command).to receive(:system_snapshot).and_return(empty_snapshot)
      ENV["HOMEBREW_SNAPSHOT_BEFORE"] = JSON.generate(empty_snapshot)

      expect { command.run }.not_to change(Homebrew, :failed?)
    end
  end
end
