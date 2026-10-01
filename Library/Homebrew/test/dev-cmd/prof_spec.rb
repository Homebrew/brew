# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/prof"

RSpec.describe Homebrew::DevCmd::Prof do
  it_behaves_like "parseable arguments"

  describe "#run" do
    before do
      allow(Utils::GemSetup).to receive(:install_bundler_gems!)
      allow(Utils::GemSetup).to receive(:setup_gem_environment!)
    end

    it "does not open HTML profiles outside a TTY" do
      prof = described_class.new(["help"])

      allow($stdout).to receive(:tty?).and_return(false)
      expect(SystemCommand).to receive(:safe_system)
        .with("ruby-prof", "--printer=call_stack", "--file=prof/call_stack.html",
              Utils::Path.resolved_path(HOMEBREW_LIBRARY_PATH/"brew.rb"), "--", "help")
      expect(Utils::Browser).not_to receive(:open)

      prof.run
    end

    it "runs Vernier without passing it to child Ruby processes" do
      prof = described_class.new(["--vernier", "commands"])

      expect(SystemCommand).to receive(:safe_system)
        .with(
          RUBY_PATH,
          "-I",
          (Pathname(Gem::Specification.find_by_name("vernier").full_gem_path)/"lib").to_s,
          "-r",
          "vernier/autorun",
          "-r",
          (HOMEBREW_LIBRARY_PATH/"prof/vernier_fork_guard").to_s,
          Utils::Path.resolved_path(HOMEBREW_LIBRARY_PATH/"brew.rb"),
          "commands",
          env: {
            "HOMEBREW_SPAWN_SYSTEM"       => "1",
            "VERNIER_ALLOCATION_INTERVAL" => "500",
            "VERNIER_OUTPUT"              => "prof/vernier.json",
          },
        )
      allow(prof).to receive(:ohai)
      allow(prof).to receive(:puts)

      prof.run
    end

    it "records phase timings without loading a sampling profiler" do
      prof = described_class.new(["--timings", "help"])

      expect(Utils::GemSetup).not_to receive(:install_bundler_gems!)
      expect(Utils::GemSetup).not_to receive(:setup_gem_environment!)
      expect(SystemCommand).to receive(:safe_system)
        .with(
          *HOMEBREW_RUBY_EXEC_ARGS,
          Utils::Path.resolved_path(HOMEBREW_LIBRARY_PATH/"brew.rb"),
          "help",
          env: { "HOMEBREW_PHASE_TIMINGS" => "prof/timings.json" },
        )
      allow(prof).to receive(:ohai)

      prof.run
    end
  end

  describe "integration tests", :integration_test, :needs_network do
    after do
      FileUtils.rm_f [
        HOMEBREW_LIBRARY_PATH/"prof/call_stack.html",
        HOMEBREW_LIBRARY_PATH/"prof/d3-flamegraph.html",
        HOMEBREW_LIBRARY_PATH/"prof/stackprof.dump",
        HOMEBREW_LIBRARY_PATH/"prof/timings.json",
        HOMEBREW_LIBRARY_PATH/"prof/vernier.json",
      ]
    end

    it "works using ruby-prof (the default)" do
      expect { brew "prof", "help", "HOMEBREW_BROWSER" => "echo" }
        .to output(/^Example usage:/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end

    it "works using stackprof" do
      expect { brew "prof", "--stackprof", "help", "HOMEBREW_BROWSER" => "echo" }
        .to output(/^Example usage:/).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end

    it "works using vernier with child processes" do
      expect { brew "prof", "--vernier", "config" }
        .to output(/^HOMEBREW_VERSION:/).to_stdout
        .and be_a_success
    end

    it "records fetch phases" do
      setup_test_formula "testball"

      expect do
        brew "prof", "--timings", "--", "fetch", "--force", "testball",
             "HOMEBREW_NO_INSTALL_FROM_API" => "1"
      end.to be_a_success

      timings = JSON.parse((HOMEBREW_LIBRARY_PATH/"prof/timings.json").read)
      phases = timings.fetch("events").map { |event| event.fetch("phase") }
      expect(phases).to include(
        "startup", "cli_parse", "command_load", "formula_resolution", "formula_inflation", "download_enqueue",
        "curl_body", "checksum", "symlink"
      )
    end
  end
end
