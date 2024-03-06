# typed: true
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    # Artifact corresponding to the `manpage` stanza.
    class Manpage < Symlinked
      attr_reader :section

      def self.from_args(cask, source)
        section = source.to_s[/\.([1-8]|n|l)(?:\.gz)?$/, 1]

        raise CaskInvalidError, "'#{source}' is not a valid man page name" unless section

        new(cask, source, section)
      end

      def initialize(cask, source, section)
        @section = section

        super(cask, source)
      end

      def resolve_target(target)
        config.manpagedir.join("man#{section}", target)
      end
    end
  end
end
