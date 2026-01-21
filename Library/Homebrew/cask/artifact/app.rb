# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `app` stanza.
    class App < Moved
      sig {
        params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          successor:    T.nilable(Cask),
          reinstall:    T::Boolean,
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(
        adopt: false,
        auto_updates: false,
        force: false,
        verbose: false,
        predecessor: nil,
        successor: nil,
        reinstall: false,
        command: SystemCommand
      )
        super

        return if target.ascend.none? { OS::Mac.system_dir?(it) }

        odebug "Fixing up '#{target}' permissions for installation to '#{target.parent}'"
        # Ensure that globally installed applications can be accessed by all users.
        # We shell out to `chmod` instead of using `FileUtils.chmod` so that using `+X` works correctly.
        command.run!("chmod", args: ["-R", "a+rX", target], sudo: !target.writable?)
      end
    end
  end
end
