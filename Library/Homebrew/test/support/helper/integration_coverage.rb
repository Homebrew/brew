# typed: true
# frozen_string_literal: true

require "coverage"
require "json"

module Homebrew
  module TestIntegrationCoverage
    DIRECTORY_ENV = "HOMEBREW_INTEGRATION_COVERAGE_DIR"
    private_constant :DIRECTORY_ENV

    class << self
      def prepare!
        require "fileutils"

        directory = File.join(
          SimpleCov.coverage_path,
          ".integration#{ENV.fetch("TEST_ENV_NUMBER", "")}",
        )
        FileUtils.rm_rf directory
        FileUtils.mkdir_p directory
        ENV[DIRECTORY_ENV] = directory
        Kernel.at_exit { store_results!(directory) }
      end

      def start!
        Coverage.start(lines: true, branches: true, eval: true)
        Kernel.at_exit { dump! }
      end

      def dump!
        return unless Coverage.running?

        directory = ENV.fetch(DIRECTORY_ENV)
        result_path = File.join(directory, "#{ENV.fetch("HOMEBREW_INTEGRATION_TEST")}.json")
        temporary_path = "#{result_path}.#{Process.pid}.tmp"
        File.write(temporary_path, JSON.generate(Coverage.result))
        File.rename(temporary_path, result_path)
      end

      def store_results!(directory)
        accumulator = SimpleCov::Combine::CoverageAccumulator.new
        Dir.glob(File.join(directory, "*.json")).each do |path|
          coverage = JSON.parse(File.read(path))
          coverage = SimpleCov::UselessResultsRemover.call(coverage)
          accumulator.absorb(coverage)
        end
        result = accumulator.result
        return if result.nil?

        command_name = "brew_i:#{Process.pid}:#{ENV.fetch("TEST_ENV_NUMBER", "")}"
        SimpleCov::ResultMerger.store_result(SimpleCov::Result.new(result, command_name:))
      ensure
        require "fileutils"

        FileUtils.rm_rf directory
        ENV.delete(DIRECTORY_ENV) if ENV[DIRECTORY_ENV] == directory
      end
    end
  end
end

Homebrew::TestIntegrationCoverage.start! if ENV["HOMEBREW_INTEGRATION_TEST"]
