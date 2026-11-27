# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-ci-matrix"

RSpec.describe Homebrew::DevCmd::GenerateCaskCiMatrix do
  it_behaves_like "parseable arguments"

  it "generates current and stable tap syntax jobs" do
    ENV["GITHUB_REPOSITORY"] = "Homebrew/homebrew-cask"
    ENV.delete("GITHUB_OUTPUT")
    command = described_class.new(["--syntax-only"])
    allow(Cask::CI::RunnerMatrix).to receive(:random_runner).and_return({ name: "macos-26" })
    stdout = StringIO.new
    allow(command).to receive(:puts) { |output| stdout.puts(output) }

    command.run

    expect(JSON.parse(stdout.string)).to eq(
      [
        {
          "name"   => "tap_syntax (macos-26)",
          "tap"    => "homebrew/cask",
          "runner" => "macos-26",
          "stable" => false,
        },
        {
          "name"       => "tap_syntax (stable) (macos-26)",
          "tap"        => "homebrew/cask",
          "runner"     => "macos-26",
          "stable"     => true,
          "skip_audit" => true,
        },
      ],
    )
  end

  it "outputs an empty runners matrix for syntax-only changes" do
    ENV["GITHUB_REPOSITORY"] = "Homebrew/homebrew-cask"
    mktmpdir do |path|
      output = path/"output"
      ENV["GITHUB_OUTPUT"] = output.to_s
      described_class.new(["--syntax-only"]).run

      expect(output.readlines(chomp: true)).to include("runners=[]")
    end
  end

  it "rejects a matrix exceeding GitHub's job limit" do
    ENV["GITHUB_REPOSITORY"] = "Homebrew/homebrew-cask"
    ENV.delete("GITHUB_OUTPUT")
    command = described_class.new(["--cask", "test"])
    allow(command).to receive(:generate_matrix).and_return(Array.new(Cask::CI::RunnerMatrix::MAX_JOBS - 1,
                                                                     {}))

    expect { command.run }
      .to output("Error: Maximum job matrix size exceeded: 257/256\n").to_stderr
      .and raise_error(SystemExit)
  end

  it "generates a cask matrix in a clean process", :cask, :integration_test, :no_api do
    CoreCaskTap.instance.path.cd do
      system "git", "init", "--quiet"
      system "git", "-c", "user.name=Homebrew Tests", "-c", "user.email=tests@brew.sh",
             "commit", "--quiet", "--allow-empty", "-m", "initial"
      system "git", "branch", "origin"

      # Run without the Sorbet runtime so this exercises the same `require` graph as
      # a real `brew generate-cask-ci-matrix`, which loads fewer files.
      brew_env = {
        "CI"                        => "1",
        "GITHUB_OUTPUT"             => (Pathname.pwd/"output").to_s,
        "GITHUB_REPOSITORY"         => "Homebrew/homebrew-cask",
        "HOMEBREW_SORBET_RECURSIVE" => nil,
        "HOMEBREW_SORBET_RUNTIME"   => nil,
      }

      expect do
        expect do
          brew "generate-cask-ci-matrix", "--cask", "local-caffeine", brew_env
        end.to be_a_success
      end.to output(/"token": "local-caffeine"/).to_stdout
      runners = File.readlines("output").grep(/^runners=/).fetch(0).delete_prefix("runners=")
      expect(JSON.parse(runners).map { |job| job.fetch("cask").fetch("token") }.uniq).to eq(["local-caffeine"])
    end
  end
end
