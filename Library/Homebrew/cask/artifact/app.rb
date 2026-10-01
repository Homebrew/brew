# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"
require "cask/caskroom"

module Cask
  module Artifact
    # Artifact corresponding to the `app` stanza.
    class App < Moved
      sig {
        override.params(
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

        odebug "Fixing up '#{target}' permissions for installation to '#{target.parent}'"
        system_dir = target.ascend
                           .take_while { it.to_s != Dir.home && (it.to_s != "/" || it == target.parent) }
                           .any? { OS::Mac.system_dir?(it) }
        permissions = "go-w"
        # Ensure that globally installed applications can be accessed by all users.
        permissions = "a+rX,#{permissions}" if system_dir

        # We shell out to `chmod` instead of using `FileUtils.chmod` so that using `+X` works correctly.
        command.run!("chmod", args: ["-R", permissions, target], sudo: nil)

        sudo = system_dir ? nil : false
        command.run("chgrp", args: ["-hR", Caskroom.expected_caskroom_group, target],
                             sudo:, must_succeed: system_dir, print_stderr: system_dir)
      end
    end
  end
end
