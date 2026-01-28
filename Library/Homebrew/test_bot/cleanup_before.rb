# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module TestBot
    class CleanupBefore < TestCleanup
      def run!(args:)
        test_header(:CleanupBefore)

        if tap.to_s != CoreTap.instance.name && CoreTap.instance.installed?
          reset_if_needed(CoreTap.instance.path.to_s)
        end

        Pathname.glob("*.bottle*.*").each(&:unlink)

        if ENV["HOMEBREW_GITHUB_ACTIONS"] && !ENV["GITHUB_ACTIONS_HOMEBREW_SELF_HOSTED"]
          # minimally fix brew doctor failures (a full clean takes ~5m)
          # TODO: move to extend/os
          # rubocop:todo Homebrew/MoveToExtendOS
          if OS.linux?
            # brew doctor complains
            bad_paths = %w[
              /usr/local/include/node/
              /opt/pipx_bin/ansible-config
            ].map { |path| Pathname.new(path) }

            delete_or_move bad_paths, sudo: true
          elsif OS.mac?
            delete_or_move HOMEBREW_CELLAR.glob("*")
            delete_or_move HOMEBREW_CASKROOM.glob("session-manager-plugin")

            frameworks_dir = Pathname("/Library/Frameworks")
            frameworks = %w[
              Mono.framework
              PluginManager.framework
              Python.framework
              R.framework
              Xamarin.Android.framework
              Xamarin.Mac.framework
              Xamarin.iOS.framework
            ].map { |framework| frameworks_dir/framework }

            delete_or_move frameworks, sudo: true
          end

          test "brew", "cleanup", "--prune-prefix"
        end
        # rubocop:enable Homebrew/MoveToExtendOS

        # Keep all "brew" invocations after cleanup_shared
        # (which cleans up Homebrew/brew)
        cleanup_shared
      end
    end
  end
end
