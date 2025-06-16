# typed: true
# frozen_string_literal: true

module Homebrew
  module Diagnostic
    class Checks
      def check_integration_test
        "This is an integration test" if ENV["HOMEBREW_INTEGRATION_TEST"]
      end
    end
  end

  def exec(*args)
    if ENV["HOMEBREW_TESTS_COVERAGE"] && ENV["HOMEBREW_INTEGRATION_TEST"]
      # Ensure we get coverage results before replacing the current process.
      SimpleCov.result
    end
    Kernel.exec(*args)
  end
end
