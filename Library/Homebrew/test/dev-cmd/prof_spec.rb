# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/prof"

RSpec.describe Homebrew::DevCmd::Prof do
  it_behaves_like "parseable arguments"

  describe "#run" do
    before do
      allow(Homebrew).to receive(:install_bundler_gems!)
      allow(Homebrew).to receive(:setup_gem_environment!)
    end

    it "does not open HTML profiles outside a TTY" do
      prof = Homebrew::DevCmd::Prof.new(["help"])

      allow($stdout).to receive(:tty?).and_return(false)
      expect(prof).to receive(:safe_system)
        .with("ruby-prof", "--printer=call_stack", "--file=prof/call_stack.html",
              (HOMEBREW_LIBRARY_PATH/"brew.rb").resolved_path, "--", "help")
      expect(prof).not_to receive(:exec_browser)

      prof.run
    end

    it "runs Vernier without passing it to child Ruby processes" do
      prof = Homebrew::DevCmd::Prof.new(["--vernier", "commands"])

      expect(prof).to receive(:safe_system)
        .with(
          { "HOMEBREW_SPAWN_SYSTEM" => "1",
            "VERNIER_ALLOCATION_INTERVAL" => "500", "VERNIER_OUTPUT" => "prof/vernier.json" },
          RUBY_PATH,
          "-I",
          (Pathname(Gem::Specification.find_by_name("vernier").full_gem_path)/"lib").to_s,
          "-r",
          "vernier/autorun",
          "-r",
          (HOMEBREW_LIBRARY_PATH/"prof/vernier_fork_guard").to_s,
          (HOMEBREW_LIBRARY_PATH/"brew.rb").resolved_path,
          "commands",
        )
      allow(prof).to receive(:ohai)
      allow(prof).to receive(:puts)

      prof.run
    end
  end

  describe "integration tests", :integration_test, :needs_network do
    after do
      FileUtils.rm_f [
        HOMEBREW_LIBRARY_PATH/"prof/call_stack.html",
        HOMEBREW_LIBRARY_PATH/"prof/d3-flamegraph.html",
        HOMEBREW_LIBRARY_PATH/"prof/stackprof.dump",
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
  end
end
