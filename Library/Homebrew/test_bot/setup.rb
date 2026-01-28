# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module TestBot
    class Setup < Test
      def run!(args:)
        test_header(:Setup)

        test "brew", "install-bundler-gems", "--add-groups=ast,audit,bottle,formula_test,livecheck,style"

        # Always output `brew config` output even when it doesn't fail.
        test "brew", "config", verbose: true

        if ENV["HOMEBREW_TEST_BOT_VERBOSE_DOCTOR"]
          test "brew", "doctor", "--debug", verbose: true
        else
          test "brew", "doctor"
        end
      end
    end
  end
end
