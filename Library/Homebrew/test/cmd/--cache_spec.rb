# typed: strict
# frozen_string_literal: true

require "cmd/--cache"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Cache do
  it_behaves_like "parseable arguments"

  it "prints all cache files for a given Formula" do
    expect { described_class.new(["--formula", (TEST_FIXTURE_DIR/"testball.rb").to_s]).run }
      .to output(%r{#{HOMEBREW_CACHE}/downloads/[\da-f]{64}--testball-}o).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints the cache files for a given Cask" do
    expect { described_class.new(["--cask", cask_path("local-caffeine").to_s]).run }
      .to output(%r{#{HOMEBREW_CACHE}/downloads/[\da-f]{64}--caffeine\.zip}o).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints the cache file for a source Cask without an installable artifact" do
    expect { described_class.new(["--cask", cask_path("naked-executable").to_s]).run }
      .to output(%r{#{HOMEBREW_CACHE}/downloads/[\da-f]{64}--naked_executable\n}o).to_stdout
      .and not_to_output.to_stderr
  end

  it "prints the cache file for a given Cask on the given operating system" do
    expect { described_class.new(["--cask", "--os=linux", cask_path("on-linux-blocks").to_s]).run }
      .to output(%r{#{HOMEBREW_CACHE}/downloads/[\da-f]{64}--caffeine-linux\.zip}o).to_stdout
      .and not_to_output.to_stderr
  end

  it "warns for a given Cask that does not support the given operating system" do
    expect do
      described_class.new(["--cask", "--os=linux", "--arch=arm", cask_path("with-depends-on-macos-bare").to_s]).run
    end
      .to output("Warning: Cask with-depends-on-macos-bare is not supported on os linux and arch arm\n").to_stderr
      .and not_to_output.to_stdout
  end

  it "warns for a given Cask that does not support the given architecture" do
    expect { described_class.new(["--cask", "--arch=intel", cask_path("depends-on-arch-arm64").to_s]).run }
      .to output(/is not supported on os \w+ and arch intel\n/).to_stderr
      .and not_to_output.to_stdout
  end

  it "warns for a Linux-only Cask with `--os=macos`" do
    expect do
      described_class.new(["--cask", "--os=macos", "--arch=arm", cask_path("with-depends-on-linux-bare").to_s]).run
    end
      .to output(/is not supported on os macos and arch arm\n/).to_stderr
      .and not_to_output.to_stdout
  end

  it "only shows the current platform for a Cask loaded from the API" do
    api_cask = Cask::Cask.new("api-cask", loaded_from_api: true) do
      version "1.2.3"
      sha256 "67cdb8a4a4d0e4f5f8c1f0b3b7f1c4d8e2a6b9c0d1e2f3a4b5c6d7e8f9a0b1c2"
      url "https://brew.sh/api-cask-1.2.3.zip"
      app "Api.app"
    end
    allow(Cask::CaskLoader).to receive(:load).and_return(api_cask)

    expect do
      Homebrew::SimulateSystem.with(os: :sequoia, arch: :arm) do
        described_class.new(["--cask", "--os=all", "api-cask"]).run
      end
    end
      .to output(%r{\A#{HOMEBREW_CACHE}/downloads/[\da-f]{64}--api-cask-1\.2\.3\.zip\n\z}o).to_stdout
      .and output(/\AWarning: Cask api-cask was loaded from the API; only showing .*\n\z/).to_stderr
  end

  it "prints the cache files for a given Formula and Cask", :integration_test do
    expect { brew "--cache", testball, cask_path("local-caffeine") }
      .to output(
        %r{
          #{HOMEBREW_CACHE}/downloads/[\da-f]{64}--testball-.*\n
          #{HOMEBREW_CACHE}/downloads/[\da-f]{64}--caffeine\.zip
        }xo,
      ).to_stdout
      .and output(/Treating .* as a formula.*Treating .* as a cask/m).to_stderr
      .and be_a_success
  end
end
