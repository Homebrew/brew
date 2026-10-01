# typed: strict
# frozen_string_literal: true

require "trust"

module Homebrew
  module TestBot
    class CleanupBefore < TestCleanup
      sig { params(args: Homebrew::Cmd::TestBotCmd::Args).void }
      def run!(args:)
        test_header(:CleanupBefore)

        if tap.to_s != CoreTap.instance.name && CoreTap.instance.installed?
          reset_if_needed(CoreTap.instance.path.to_s)
        end

        Pathname.glob("*.bottle*.*").each(&:unlink)

        if ENV["HOMEBREW_GITHUB_ACTIONS"] && !ENV["GITHUB_ACTIONS_HOMEBREW_SELF_HOSTED"]
          # minimally fix brew doctor failures (a full clean takes ~5m)
          cleanup_github_actions_hosted_runner
          untap_untrusted_taps
          test "brew", "cleanup", "--prune-prefix"
        end

        # Keep all "brew" invocations after cleanup_shared
        # (which cleans up Homebrew/brew)
        cleanup_shared
        Homebrew::TestBot.trust_test_tap!(tap)
      end

      sig { void }
      def cleanup_github_actions_hosted_runner; end

      sig { void }
      def untap_untrusted_taps
        taps_to_untap = Homebrew::Trust.untrusted_taps.reject { |untrusted_tap| untrusted_tap.name == tap&.name }
        return if taps_to_untap.empty?

        test "brew", "untap", "--force", *taps_to_untap.map(&:name)
      end
    end
  end
end
