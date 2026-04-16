# typed: strict
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    # Artifact corresponding to the `manpage` stanza.
    class Manpage < Symlinked
      sig { returns(String) }
      attr_reader :section

      sig {
        override.params(
          cask:         Cask,
          source:       T.any(String, Pathname),
          _target_hash: T.anything,
        ).returns(T.attached_class)
      }
      def self.from_args(cask, source, _target_hash = nil)
        section = source.to_s[/\.([1-8]|n|l)(?:\.gz)?$/, 1]

        raise CaskInvalidError, "'#{source}' is not a valid man page name" unless section

        new(cask, source, section)
      end

      sig { params(cask: Cask, source: T.any(String, Pathname), section: String).void }
      def initialize(cask, source, section)
        @section = section

        super(cask, source)
      end

      sig { override.params(target: T.any(String, Pathname), base_dir: T.nilable(Pathname)).returns(Pathname) }
      def resolve_target(target, base_dir: nil)
        config.manpagedir.join("man#{section}", target)
      end
    end
  end
end
