# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"
require "hardware"
require "system_command"

module Homebrew
  module DevCmd
    class Tests < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        description <<~EOS
          Run Homebrew's unit and integration tests.
        EOS
        switch "--coverage",
               description: "Generate code coverage reports."
        switch "--generic",
               description: "Run only OS-agnostic tests."
        switch "--online",
               description: "Include tests that use the GitHub API and tests that use any of the taps for " \
                            "official external commands."
        switch "--debug",
               description: "Enable debugging using `ruby/debug`, or surface the standard `odebug` output."
        switch "--changed",
               description: "Only runs tests on files that were changed from the master branch."
        switch "--fail-fast",
               description: "Exit early on the first failing test."
        switch "--no-parallel",
               description: "Run tests serially."
        flag   "--only=",
               description: "Run only `<test_script>_spec.rb`. Appending `:<line_number>` will start at a " \
                            "specific line."
        flag   "--profile=",
               description: "Run the test suite serially to find the <n> slowest tests."
        flag   "--seed=",
               description: "Randomise tests with the specified <value> instead of a random seed."

        conflicts "--changed", "--only"

        named_args :none
      end

      sig { override.void }
      def run
        # Given we might be testing various commands, we probably want everything (except sorbet-static)
        Homebrew.install_bundler_gems!(groups: Homebrew.valid_gem_groups - ["sorbet"])

        HOMEBREW_LIBRARY_PATH.cd do
          setup_environment!

          # Needs required here, after `setup_environment!`, so that
          # `HOMEBREW_TEST_GENERIC_OS` is set and `OS.linux?` and `OS.mac?` both
          # `return false`.
          require "extend/os/dev-cmd/tests"

          parallel = !args.no_parallel?

          only = args.only
          files = if only
            test_name, line = only.split(":", 2)

            if line.nil?
              Dir.glob("test/{#{test_name},#{test_name}/**/*}_spec.rb")
            else
              parallel = false
              ["test/#{test_name}_spec.rb:#{line}"]
            end
          elsif args.changed?
            changed_test_files
          else
            Dir.glob("test/**/*_spec.rb")
          end

          if files.blank?
            raise UsageError, "The `--only` argument requires a valid file or folder name!" if only

            if args.changed?
              opoo "No tests are directly associated with the changed files!"
              return
            end
          end

          # We use `ParallelTests.last_process?` in `test/spec_helper.rb` to
          # handle SimpleCov output but, due to how the method is implemented,
          # it doesn't work as expected if the number of processes is greater
          # than one but lower than the number of CPU cores in the execution
          # environment. Coverage information isn't saved in that scenario,
          # so we disable parallel testing as a workaround in this case.
          parallel = false if args.profile || (args.coverage? && files.length < Hardware::CPU.cores)

          parallel_rspec_log_name = "parallel_runtime_rspec"
          parallel_rspec_log_name = "#{parallel_rspec_log_name}.generic" if args.generic?
          parallel_rspec_log_name = "#{parallel_rspec_log_name}.online" if args.online?
          parallel_rspec_log_name = "#{parallel_rspec_log_name}.log"

          parallel_rspec_log_path = if ENV["CI"]
            "tests/#{parallel_rspec_log_name}"
          else
            "#{HOMEBREW_CACHE}/#{parallel_rspec_log_name}"
          end
          ENV["PARALLEL_RSPEC_LOG_PATH"] = parallel_rspec_log_path

          parallel_args = if ENV["CI"]
            %W[
              --combine-stderr
              --serialize-stdout
              --runtime-log #{parallel_rspec_log_path}
            ]
          else
            %w[
              --nice
            ]
          end

          # Generate seed ourselves and output later to avoid multiple different
          # seeds being output when running parallel tests.
          seed = args.seed || rand(0xFFFF).to_i

          bundle_args = ["-I", HOMEBREW_LIBRARY_PATH/"test"]
          bundle_args += %W[
            --seed #{seed}
            --color
            --require spec_helper
          ]
          bundle_args << "--fail-fast" if args.fail_fast?
          bundle_args << "--profile" << args.profile if args.profile
          bundle_args << "--tag" << "~needs_arm" unless Hardware::CPU.arm?
          bundle_args << "--tag" << "~needs_intel" unless Hardware::CPU.intel?
          bundle_args << "--tag" << "~needs_network" unless args.online?
          bundle_args << "--tag" << "~needs_ci" unless ENV["CI"]

          bundle_args = os_bundle_args(bundle_args)
          files = os_files(files)

          puts "Randomized with seed #{seed}"

          ENV["HOMEBREW_DEBUG"] = "1" if args.debug? # Used in spec_helper.rb to require the "debug" gem.

          # Workaround for:
          #
          # ```
          # ruby: no -r allowed while running setuid (SecurityError)
          # ```
          Process::UID.change_privilege(Process.euid) if Process.euid != Process.uid

          if parallel
            system "bundle", "exec", "parallel_rspec", *parallel_args, "--", *bundle_args, "--", *files
          else
            system "bundle", "exec", "rspec", *bundle_args, "--", *files
          end
          success = $CHILD_STATUS.success?

          return if success

          Homebrew.failed = true
        end
      end

      private

      sig { params(bundle_args: T::Array[String]).returns(T::Array[String]) }
      def os_bundle_args(bundle_args)
        # for generic tests, remove macOS or Linux specific tests
        non_linux_bundle_args(non_macos_bundle_args(bundle_args))
      end

      sig { params(bundle_args: T::Array[String]).returns(T::Array[String]) }
      def non_macos_bundle_args(bundle_args)
        bundle_args << "--tag" << "~needs_homebrew_core" if ENV["CI"]
        bundle_args << "--tag" << "~needs_svn" unless args.online?

        bundle_args << "--tag" << "~needs_macos" << "--tag" << "~cask"
      end

      sig { params(bundle_args: T::Array[String]).returns(T::Array[String]) }
      def non_linux_bundle_args(bundle_args)
        bundle_args << "--tag" << "~needs_linux" << "--tag" << "~needs_systemd"
      end

      sig { params(files: T::Array[String]).returns(T::Array[String]) }
      def os_files(files)
        # for generic tests, remove macOS or Linux specific files
        non_linux_files(non_macos_files(files))
      end

      sig { params(files: T::Array[String]).returns(T::Array[String]) }
      def non_macos_files(files)
        files.grep_v(%r{^test/(os/mac|cask)(/.*|_spec\.rb)$})
      end

      sig { params(files: T::Array[String]).returns(T::Array[String]) }
      def non_linux_files(files)
        files.grep_v(%r{^test/os/linux(/.*|_spec\.rb)$})
      end

      sig { returns(T::Array[String]) }
      def changed_test_files
        changed_files = Utils.popen_read("git", "diff", "--name-only", "master")

        raise UsageError, "No files have been changed from the master branch!" if changed_files.blank?

        filestub_regex = %r{Library/Homebrew/([\w/-]+).rb}
        changed_files.scan(filestub_regex).map(&:last).filter_map do |filestub|
          if filestub.start_with?("test/")
            # Only run tests on *_spec.rb files in test/ folder
            filestub.end_with?("_spec") ? Pathname("#{filestub}.rb") : nil
          else
            # For all other changed .rb files guess the associated test file name
            Pathname("test/#{filestub}_spec.rb")
          end
        end.select(&:exist?)
      end

      sig { returns(T::Array[String]) }
      def setup_environment!
        # Cleanup any unwanted user configuration.
        allowed_test_env = %w[
          HOMEBREW_GITHUB_API_TOKEN
          HOMEBREW_CACHE
          HOMEBREW_LOGS
          HOMEBREW_TEMP
        ]
        allowed_test_env << "HOMEBREW_USE_RUBY_FROM_PATH" if Homebrew::EnvConfig.developer?
        Homebrew::EnvConfig::ENVS.keys.map(&:to_s).each do |env|
          next if allowed_test_env.include?(env)

          ENV.delete(env)
        end

        # Codespaces HOMEBREW_PREFIX and /tmp are mounted 755 which makes Ruby warn constantly.
        if (ENV["HOMEBREW_CODESPACES"] == "true") && (HOMEBREW_TEMP.to_s == "/tmp")
          # Need to keep this fairly short to avoid socket paths being too long in tests.
          homebrew_prefix_tmp = "/home/linuxbrew/tmp"
          ENV["HOMEBREW_TEMP"] = homebrew_prefix_tmp
          FileUtils.mkdir_p homebrew_prefix_tmp
          system "chmod", "-R", "g-w,o-w", HOMEBREW_PREFIX, homebrew_prefix_tmp
        end

        ENV["HOMEBREW_TESTS"] = "1"
        ENV["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        ENV["HOMEBREW_NO_ANALYTICS_THIS_RUN"] = "1"
        ENV["HOMEBREW_TEST_GENERIC_OS"] = "1" if args.generic?
        ENV["HOMEBREW_TEST_ONLINE"] = "1" if args.online?
        ENV["HOMEBREW_SORBET_RUNTIME"] = "1"
        ENV["HOMEBREW_NO_FORCE_BREW_WRAPPER"] = "1"

        ENV["USER"] ||= system_command!("id", args: ["-nu"]).stdout.chomp

        # Avoid local configuration messing with tests, e.g. git being configured
        # to use GPG to sign by default
        ENV["HOME"] = "#{HOMEBREW_LIBRARY_PATH}/test"

        # Print verbose output when requesting debug or verbose output.
        ENV["HOMEBREW_VERBOSE_TESTS"] = "1" if args.debug? || args.verbose?

        if args.coverage?
          ENV["HOMEBREW_TESTS_COVERAGE"] = "1"
          FileUtils.rm_f "test/coverage/.resultset.json"
        end

        # Override author/committer as global settings might be invalid and thus
        # will cause silent failure during the setup of dummy Git repositories.
        %w[AUTHOR COMMITTER].each do |role|
          ENV["GIT_#{role}_NAME"] = "brew tests"
          ENV["GIT_#{role}_EMAIL"] = "brew-tests@localhost"
          ENV["GIT_#{role}_DATE"]  = "Sun Jan 22 19:59:13 2017 +0000"
        end
      end
    end
  end
end
