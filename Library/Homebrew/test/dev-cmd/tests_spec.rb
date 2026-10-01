# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/tests"
require "parallel_tests/rspec/runner"

RSpec.describe Homebrew::DevCmd::Tests do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "tests"

  describe "#run" do
    subject(:tests) { described_class.new(args) }

    let(:args) { [] }

    before do
      allow(Utils::GemSetup).to receive_messages(valid_gem_groups: [], install_bundler_gems!: nil)
      allow(tests).to receive_messages(setup_environment!: nil, check_test_environment!: nil)
    end

    context "when changed tests only run on another OS" do
      let(:args) { ["--changed"] }
      let(:changed_file) do
        if OS.linux?
          "Library/Homebrew/cask/cask.rb"
        else
          "Library/Homebrew/os/linux/ld.rb"
        end
      end

      before do
        allow(Utils::Git).to receive(:changed_files).and_return([changed_file])
      end

      it "does not invoke RSpec" do
        expect(tests).not_to receive(:system)

        expect { tests.run }.to output(/No tests are available to run on this operating system/).to_stderr
      end
    end

    context "when an explicit test only runs on another OS" do
      let(:args) { ["--only=#{test_name}"] }
      let(:test_name) { OS.linux? ? "cask/cask" : "os/linux/ld" }

      it "fails instead of reporting success without running the test" do
        expect(tests).not_to receive(:system)

        expect { tests.run }.to raise_error(UsageError, /No tests are available to run on this operating system/)
      end
    end

    context "when loading tests without running examples" do
      let(:args) { ["--load-only", "--no-parallel", "--only=warnings,exceptions"] }

      it "loads each selected file in a separate RSpec process" do
        invoked_arguments = T.let([], T::Array[String])
        allow(tests).to receive(:system) do |*arguments|
          invoked_arguments = arguments
          system "/usr/bin/true"
        end

        tests.run

        expect(invoked_arguments)
          .to start_with("bundle", "exec", "parallel_rspec")
          .and array_including_cons("--test-file-limit", "1", "-n", "1", "--")
          .and include("--dry-run")
          .and end_with("--", "test/warnings_spec.rb", "test/exceptions_spec.rb")
      end
    end

    context "when loading a line-qualified test" do
      let(:args) { ["--load-only", "--only=warnings:7"] }

      it "loads the entire file" do
        invoked_arguments = T.let([], T::Array[String])
        allow(tests).to receive(:system) do |*arguments|
          invoked_arguments = arguments
          system "/usr/bin/true"
        end

        tests.run

        expect(invoked_arguments).to end_with("--", "test/warnings_spec.rb")
      end
    end

    context "when grouping parallel tests" do
      def invoked_arguments
        captured = T.let([], T::Array[String])
        allow(tests).to receive(:system) do |*arguments|
          captured = arguments
          system "/usr/bin/true"
        end
        tests.run
        captured
      end

      let(:log_path) { "#{HOMEBREW_CACHE}/parallel_runtime_rspec.log" }

      before do
        # The log lives in `HOMEBREW_CACHE` locally and in `tests/` on CI, so pin
        # the local path rather than inheriting whichever the runner happens to be.
        ENV.delete("CI")
        allow(Dir).to receive(:glob).with("test/**/*_spec.rb")
                                    .and_return(%w[test/a_spec.rb test/b_spec.rb])
      end

      it "groups by recorded runtime rather than file size" do
        expect(invoked_arguments).to array_including_cons("--runtime-log", log_path)
      end

      it "records the runtimes of a full run" do
        invoked_arguments

        expect(ENV.fetch("PARALLEL_RSPEC_LOG_PATH")).to eq(log_path)
      end

      it "groups by the cached log on CI" do
        ENV["CI"] = "1"

        expect(invoked_arguments).to array_including_cons("--runtime-log", "tests/parallel_runtime_rspec.log")
      end

      context "when exiting on the first failure" do
        let(:args) { ["--fail-fast"] }

        it "does not replace the recorded runtimes" do
          invoked_arguments

          expect(ENV.fetch("PARALLEL_RSPEC_LOG_PATH")).to eq("#{log_path}.partial")
        end
      end

      context "when only one shard is selected" do
        let(:args) { ["--shard=1/2"] }

        before do
          allow(ParallelTests::RSpec::Runner).to receive(:tests_in_groups)
            .and_return([%w[test/a_spec.rb], %w[test/b_spec.rb]])
        end

        it "does not replace the recorded runtimes" do
          invoked_arguments

          expect(ENV.fetch("PARALLEL_RSPEC_LOG_PATH")).to eq("#{log_path}.partial")
        end
      end

      context "when only changed files are selected" do
        let(:args) { ["--changed"] }

        before do
          allow(Utils::Git).to receive(:changed_files)
            .and_return(["Library/Homebrew/test/warnings_spec.rb"])
        end

        it "does not replace the recorded runtimes" do
          invoked_arguments

          expect(ENV.fetch("PARALLEL_RSPEC_LOG_PATH")).to eq("#{log_path}.partial")
        end
      end

      context "when only some files are selected" do
        let(:args) { ["--only=warnings"] }

        before do
          allow(Dir).to receive(:glob).with("test/{warnings,warnings/**/*}_spec.rb")
                                      .and_return(%w[test/warnings_spec.rb])
        end

        it "still groups by the recorded runtimes" do
          expect(invoked_arguments).to array_including_cons("--runtime-log", log_path)
        end

        it "does not replace the recorded runtimes" do
          invoked_arguments

          expect(ENV.fetch("PARALLEL_RSPEC_LOG_PATH")).to eq("#{log_path}.partial")
        end
      end
    end

    context "when sharding tests" do
      let(:args) { ["--shard=2/2"] }

      it "runs only the selected shard" do
        ENV["CI"] = "1"
        allow(Dir).to receive(:glob).with("test/**/*_spec.rb")
                                    .and_return(%w[test/a_spec.rb test/b_spec.rb test/c_spec.rb test/d_spec.rb])
        expect(ParallelTests::RSpec::Runner).to receive(:tests_in_groups)
          .with(%w[test/a_spec.rb test/b_spec.rb test/c_spec.rb test/d_spec.rb], 2,
                runtime_log: "tests/parallel_runtime_rspec.log")
          .and_return([
            %w[test/a_spec.rb test/c_spec.rb],
            %w[test/b_spec.rb test/d_spec.rb],
          ])
        invoked_arguments = T.let([], T::Array[String])
        allow(tests).to receive(:system) do |*arguments|
          invoked_arguments = arguments
          system "/usr/bin/true"
        end

        tests.run

        expect(invoked_arguments).to end_with("--", "test/b_spec.rb", "test/d_spec.rb")
      end
    end
  end

  describe "#ensure_test_dependency!" do
    include Test::Helper::Dependencies

    it "fails when a dependency is missing on CI" do
      ENV["CI"] = "1"
      ENV.delete("HOMEBREW_TEST_BOT")

      expect { ensure_test_dependency!(false, "Dependency is not installed.") }
        .to raise_error(RuntimeError, "Dependency is not installed.")
    end

    it "skips when a dependency is missing under `brew test-bot`" do
      ENV["CI"] = "1"
      ENV["HOMEBREW_TEST_BOT"] = "1"

      expect(self).to receive(:skip).with("Dependency is not installed.")
      ensure_test_dependency!(false, "Dependency is not installed.")
    end
  end

  describe "#check_test_environment!", :needs_linux do
    subject(:tests) { described_class.new([]) }

    before do
      require "extend/os/linux/dev-cmd/tests"
      require "sandbox"

      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_return(true)
      allow(GitHub::Actions).to receive(:env_set?).and_return(false)
    end

    it "does not require the Linux sandbox when Linux sandboxing is disabled" do
      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_return(false)
      allow(Sandbox).to receive_messages(available?: false, failure_reason: "sandbox unavailable")

      expect { tests.check_test_environment! }.not_to output.to_stderr
    end

    it "raises on GitHub Actions when the Linux sandbox is unavailable" do
      allow(Sandbox).to receive_messages(available?: false, failure_reason: "Landlock is not available.")
      allow(GitHub::Actions).to receive(:env_set?).and_return(true)

      expect { tests.check_test_environment! }.to raise_error(RuntimeError, "Landlock is not available.")
    end

    it "warns instead of failing outside GitHub Actions when the Linux sandbox is unavailable" do
      allow(Sandbox).to receive_messages(available?: false, failure_reason: "Landlock is not available.")

      expect { tests.check_test_environment! }.to output(/Landlock is not available\./).to_stderr
    end

    it "passes when the Linux sandbox is available" do
      allow(Sandbox).to receive(:available?).and_return(true)

      expect { tests.check_test_environment! }.not_to raise_error
    end
  end

  describe "#setup_environment!" do
    subject(:tests) { described_class.new([]) }

    before do
      require "api"

      allow(Homebrew::API).to receive(:fetch_api_files!)
    end

    it "keeps generic cache files out of the sandboxed test home" do
      tests.setup_environment!

      expect(ENV.fetch("XDG_CACHE_HOME")).to eq("#{HOMEBREW_CACHE}/tests")
      expect(ENV.fetch("XDG_CACHE_HOME")).not_to start_with("#{Dir.home}/")
    end

    it "keeps generic tool state out of the sandboxed test home" do
      tests.setup_environment!

      expect(ENV.fetch("XDG_STATE_HOME")).to eq("#{HOMEBREW_CACHE}/tests-state")
      expect(ENV.fetch("XDG_STATE_HOME")).not_to start_with("#{Dir.home}/")
    end

    it "can disable Sorbet runtime" do
      ENV["HOMEBREW_TESTS_NO_SORBET_RUNTIME"] = "1"
      tests.setup_environment!

      expect([
        ENV.fetch("HOMEBREW_TESTS_NO_SORBET_RUNTIME", nil),
        ENV.fetch("HOMEBREW_SORBET_RUNTIME", nil),
        ENV.fetch("HOMEBREW_SORBET_RECURSIVE", nil),
      ]).to eq(["1", nil, nil])
    end

    it "preserves the nested sandbox opt-in" do
      ENV["HOMEBREW_AVOID_NESTED_SANDBOXING"] = "1"
      tests.setup_environment!

      expect(ENV.fetch("HOMEBREW_AVOID_NESTED_SANDBOXING")).to eq("1")
    end
  end

  describe "#changed_test_files" do
    subject(:changed_test_files) { tests.changed_test_files }

    let(:tests) { described_class.new([]) }

    context "when a spec file changed" do
      let(:changed_file) { "Library/Homebrew/test/cmd/help_spec.rb\n" }

      before do
        allow(Utils::Git).to receive(:changed_files).and_return(changed_file.split("\n"))
      end

      it "includes the changed spec file" do
        expect(changed_test_files).to include("test/cmd/help_spec.rb")
      end
    end

    context "when a non-test Ruby file changed" do
      let(:changed_file) { "Library/Homebrew/cmd/help.rb\n" }

      before do
        allow(Utils::Git).to receive(:changed_files).and_return(changed_file.split("\n"))
      end

      it "maps the file to its corresponding spec" do
        expect(changed_test_files).to include("test/cmd/help_spec.rb")
      end
    end

    context "when integration shared context changed" do
      let(:changed_file) do
        "Library/Homebrew/test/support/helper/spec/shared_context/integration_test.rb\n"
      end

      before do
        allow(Utils::Git).to receive(:changed_files).and_return(changed_file.split("\n"))
      end

      it "includes integration tests and excludes unrelated tests", :aggregate_failures do
        expect(changed_test_files).to include("test/cmd/help_spec.rb")
        expect(changed_test_files).not_to include("test/dev-cmd/tests_spec.rb")
      end
    end

    context "when cask shared context changed" do
      let(:changed_file) do
        "Library/Homebrew/test/support/helper/spec/shared_context/homebrew_cask.rb\n"
      end

      before do
        allow(Utils::Git).to receive(:changed_files).and_return(changed_file.split("\n"))
      end

      it "includes cask tests and excludes non-cask tests", :aggregate_failures do
        expect(changed_test_files).to include("test/cmd/outdated_spec.rb")
        expect(changed_test_files).not_to include("test/cmd/help_spec.rb")
        expect(changed_test_files).not_to include("test/dev-cmd/pr-pull_spec.rb")
        expect(changed_test_files).not_to include("test/cmd/bundle/cleanup_subcommand_spec.rb")
      end
    end
  end
end
