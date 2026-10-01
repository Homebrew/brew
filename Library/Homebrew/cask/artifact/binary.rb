# typed: strict
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    # Artifact corresponding to the `binary` stanza.
    class Binary < Symlinked
      sig {
        override.params(
          force:     T::Boolean,
          adopt:     T::Boolean,
          overwrite: T::Boolean,
          dry_run:   T::Boolean,
          command:   T.class_of(SystemCommand),
        ).void
      }
      def link(force: false, adopt: false, overwrite: false, dry_run: false, command: SystemCommand)
        super
        return if dry_run || source.executable?

        if source.writable?
          FileUtils.chmod "+x", source
        else
          command.run!("chmod", args: ["+x", source], sudo: nil)
        end
      end
    end
  end
end
