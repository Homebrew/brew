# typed: strict
# frozen_string_literal: true

require "cask/macos"

module OS
  module Mac
    module Cask
      module Installer
        extend T::Helpers

        requires_ancestor { ::Cask::Installer }

        sig { void }
        def prelude
          # Resolve and memoize the system languages as the first cask
          # operation: resolving them lazily later (e.g. while serializing the
          # cask config) would fork (`Utils.popen`) after this process has
          # already used fork-hostile frameworks such as Security.framework
          # for signing checks. `prelude` runs before any download, artifact
          # or signing work in installs, reinstalls and upgrades and does not
          # run at all when no casks are being processed.
          # https://github.com/Homebrew/brew/issues/23606
          MacOS.languages

          super
        end
      end
    end
  end
end

Cask::Installer.prepend(OS::Mac::Cask::Installer)
