# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    # Artifact corresponding to the `binary` stanza.
    class Binary < Symlinked
      def link(command: nil, **options)
        super
        return if source.executable?

        if source.writable?
          FileUtils.chmod "+x", source
        else
          command.run!("/bin/chmod", args: ["+x", source], sudo: true)
        end
      end
    end
  end
end
