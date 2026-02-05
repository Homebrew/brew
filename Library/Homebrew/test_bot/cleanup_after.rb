# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module TestBot
    class CleanupAfter < TestCleanup
      def run!(args:)
        if ENV["HOMEBREW_GITHUB_ACTIONS"].present? && ENV["GITHUB_ACTIONS_HOMEBREW_SELF_HOSTED"].blank? &&
           # don't need to do post-build cleanup unless testing test-bot itself.
           !args.test_default_formula?
          return
        end

        test_header(:CleanupAfter)

        pkill_if_needed

        cleanup_shared

        # Keep all "brew" invocations after cleanup_shared
        # (which cleans up Homebrew/brew)
        return unless local?(args)

        FileUtils.rm_rf ENV.fetch("HOMEBREW_HOME")
        FileUtils.rm_rf ENV.fetch("HOMEBREW_LOGS")
      end

      private

      def pkill_if_needed
        pgrep = ["pgrep", "-f", HOMEBREW_CELLAR.to_s]

        return unless quiet_system(*pgrep)

        test "pkill", "-f", HOMEBREW_CELLAR.to_s

        return unless quiet_system(*pgrep)

        sleep 1
        test "pkill", "-9", "-f", HOMEBREW_CELLAR.to_s if system(*pgrep)
      end
    end
  end
end
