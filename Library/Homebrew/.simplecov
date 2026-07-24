#!/usr/bin/env ruby
# frozen_string_literal: true

require "English"

SimpleCov.configure do
  merge_subprocesses true
  coverage_dir File.expand_path("../test/coverage", File.realpath(__FILE__))
  root File.expand_path("..", File.realpath(__FILE__))
  command_name "brew"

  # enables branch coverage as well as, the default, line coverage
  enable_coverage :branch

  # enables coverage for `eval`ed code
  enable_coverage :eval

  # ensure that we always default to line coverage
  primary_coverage :line

  # We manage the result cache ourselves and the default of 10 minutes can be
  # too low causing results from some integration tests to be dropped. This
  # causes random fluctuations in test coverage.
  merge_timeout 86400

  at_fork do
    # be quiet, the parent process will be in charge of output and checking coverage totals
    SimpleCov.print_errors false
  end
  excludes = ["test", "vendor"]
  subdirs = Dir.chdir(SimpleCov.root) { Pathname.glob("*") }
               .reject { |p| p.extname == ".rb" || excludes.include?(p.to_s) }
               .map { |p| "#{p}/**/*.rb" }.join(",")
  files = "{#{subdirs},*.rb}"

  if (integration_test_number = ENV.fetch("HOMEBREW_INTEGRATION_TEST", nil))
    # This needs a unique name so it won't be overwritten
    command_name "brew_i:#{integration_test_number}"

    # be quiet, the parent process will be in charge of output and checking coverage totals
    SimpleCov.print_errors false

    SimpleCov.at_exit do
      # Just save result, but don't write formatted output.
      coverage_result = Coverage.result.dup
      Dir.glob(files, base: SimpleCov.root).each do |file|
        absolute_path = File.expand_path(file, SimpleCov.root)
        coverage_result[absolute_path] ||= SimpleCov::SimulateCoverage.call(absolute_path)
      end
      simplecov_result = SimpleCov::Result.new(coverage_result)
      SimpleCov::ResultMerger.store_result(simplecov_result)

      # If an integration test raises a `SystemExit` exception on exit,
      # exit immediately using the same status code to avoid reporting
      # an error when expecting a non-successful exit status.
      raise if $ERROR_INFO.is_a?(SystemExit)
    end
  else
    command_name "brew:#{ENV.fetch("TEST_ENV_NUMBER", $PROCESS_ID)}"

    # Not using this during integration tests makes the tests 4x times faster
    # without changing the coverage.
    cover files
  end

  skip(/^build\.rb$/)
  skip(/^config\.rb$/)
  skip(/^constants\.rb$/)
  skip(/^postinstall\.rb$/)
  skip(/^test\.rb$/)
  skip %r{^dev-cmd/tests\.rb$}
  skip %r{^sorbet/}
  skip %r{^test/}
  skip %r{^vendor/}
  skip %r{^yard/}

  require "rbconfig"
  host_os = RbConfig::CONFIG["host_os"]
  skip %r{/os/mac} unless host_os.include?("darwin")
  skip %r{/os/linux} unless host_os.include?("linux")

  # Add groups and the proper project name to the output.
  project_name "Homebrew"
  group "Cask", %r{^cask(/|\.rb$)}
  group "Commands", [%r{^cmd/}, %r{^dev-cmd/}]
  group "Extensions", %r{^extend/}
  group "Livecheck", %r{^livecheck(/|\.rb$)}
  group "OS", [%r{^extend/os/}, %r{^os/}]
  group "Requirements", %r{^requirements/}
  group "RuboCops", %r{^rubocops/}
  group "Unpack Strategies", %r{^unpack_strategy(/|\.rb$)}
  group "Scripts", [
    /^brew\.rb$/,
    /^build\.rb$/,
    /^postinstall\.rb$/,
    /^test\.rb$/,
  ]
end
