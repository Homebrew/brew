# typed: strict
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    # Artifact corresponding to the `binary` stanza.
    class Binary < Symlinked
      sig { override.params(command: T.class_of(SystemCommand), force: T::Boolean, adopt: T::Boolean, _options: T.anything).void }
      def link(command:, force: false, adopt: false, **_options)
        super
        return if source.executable?

        if source.writable?
          FileUtils.chmod "+x", source
        else
          command.run!("chmod", args: ["+x", source], sudo: true)
        end
      end
    end
  end
end
