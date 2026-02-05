# typed: strict
# frozen_string_literal: true

require "utils/output"

module Utils
  module Backtrace
    extend Utils::Output::Mixin

    @print_backtrace_message = T.let(false, T::Boolean)

    # Cleans `sorbet-runtime` gem paths from the backtrace unless...
    # 1. `verbose` is set
    # 2. first backtrace line starts with `sorbet-runtime`
    #   - This implies that the error is related to Sorbet.
    sig { params(error: Exception).returns(T.nilable(T::Array[String])) }
    def self.clean(error)
      backtrace = error.backtrace

      return backtrace if Context.current.verbose?
      return backtrace if backtrace.blank?
      return backtrace if backtrace.fetch(0).start_with?(sorbet_runtime_path)

      old_backtrace_length = backtrace.length
      backtrace.reject { |line| line.start_with?(sorbet_runtime_path) }
               .tap { |new_backtrace| print_backtrace_message if old_backtrace_length > new_backtrace.length }
    end

    sig { returns(String) }
    def self.sorbet_runtime_path
      @sorbet_runtime_path ||= T.let("#{Gem.paths.home}/gems/sorbet-runtime", T.nilable(String))
    end

    sig { void }
    def self.print_backtrace_message
      return if @print_backtrace_message

      # This is just unactionable noise in GitHub Actions.
      opoo_outside_github_actions "Removed Sorbet lines from backtrace!"
      puts "Rerun with `--verbose` to see the original backtrace" unless Homebrew::EnvConfig.no_env_hints?

      @print_backtrace_message = true
    end

    sig { params(error: Exception).returns(T.nilable(String)) }
    def self.tap_error_url(error)
      backtrace = error.backtrace
      return if backtrace.blank?

      backtrace.each do |line|
        if (tap = line.match(%r{/Library/Taps/([^/]+/[^/]+)/}))
          return "https://github.com/#{tap[1]}/issues/new"
        end
      end

      nil
    end
  end
end
