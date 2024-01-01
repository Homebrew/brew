#!/usr/bin/env ruby
# frozen_string_literal: true

require "English"

SimpleCov.enable_for_subprocesses true

SimpleCov.start do
  coverage_dir File.expand_path("../test/coverage", File.realpath(__FILE__))
  root File.expand_path("..", File.realpath(__FILE__))
  command_name "brew"

  # enables branch coverage as well as, the default, line coverage
  enable_coverage :branch

  # We manage the result cache ourselves and the default of 10 minutes can be
  # too low causing results from some integration tests to be dropped. This
  # causes random fluctuations in test coverage.
  merge_timeout 86400

  at_fork do
    # be quiet, the parent process will be in charge of output and checking coverage totals
    SimpleCov.print_error_status = false
  end
  excludes = ["test", "vendor"]
  subdirs = Dir.chdir(SimpleCov.root) { Pathname.glob("*") }
               .reject { |p| p.extname == ".rb" || excludes.include?(p.to_s) }
               .map { |p| "#{p}/**/*.rb" }.join(",")
  files = "#{SimpleCov.root}/{#{subdirs},*.rb}"

  if (integration_test_number = ENV.fetch("HOMEBREW_INTEGRATION_TEST", nil))
    # This needs a unique name so it won't be overwritten
    command_name "brew_i:#{integration_test_number}"

    # be quiet, the parent process will be in charge of output and checking coverage totals
    SimpleCov.print_error_status = false

    SimpleCov.at_exit do
      # Just save result, but don't write formatted output.
      coverage_result = Coverage.result.dup
      Dir[files].each do |file|
        absolute_path = File.expand_path(file)
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
    track_files files
  end

  add_filter %r{^/build\.rb$}
  add_filter %r{^/config\.rb$}
  add_filter %r{^/constants\.rb$}
  add_filter %r{^/postinstall\.rb$}
  add_filter %r{^/test\.rb$}
  add_filter %r{^/dev-cmd/tests\.rb$}
  add_filter %r{^/sorbet/}
  add_filter %r{^/test/}
  add_filter %r{^/vendor/}
  add_filter %r{^/yard/}

  require "rbconfig"
  host_os = RbConfig::CONFIG["host_os"]
  add_filter %r{/os/mac} unless host_os.include?("darwin")
  add_filter %r{/os/linux} unless host_os.include?("linux")

  # Add groups and the proper project name to the output.
  project_name "Homebrew"
  add_group "Cask", %r{^/cask(/|\.rb$)}
  add_group "Commands", [%r{/cmd/}, %r{^/dev-cmd/}]
  add_group "Extensions", %r{^/extend/}
  add_group "Livecheck", %r{^/livecheck(/|\.rb$)}
  add_group "OS", [%r{^/extend/os/}, %r{^/os/}]
  add_group "Requirements", %r{^/requirements/}
  add_group "RuboCops", %r{^/rubocops/}
  add_group "Unpack Strategies", %r{^/unpack_strategy(/|\.rb$)}
  add_group "Scripts", [
    %r{^/brew\.rb$},
    %r{^/build\.rb$},
    %r{^/postinstall\.rb$},
    %r{^/test\.rb$},
  ]
end
