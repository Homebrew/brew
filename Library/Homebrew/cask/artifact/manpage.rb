# typed: strict
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    # Artifact corresponding to the `manpage` stanza.
    class Manpage < Symlinked
      sig { returns(String) }
      attr_reader :section

      sig { params(cask: Cask, source: String, _target_hash: T.anything).returns(Manpage) }
      def self.from_args(cask, source, **_target_hash)
        section = source.to_s[/\.([1-8]|n|l)(?:\.gz)?$/, 1]

        raise CaskInvalidError, "'#{source}' is not a valid man page name" unless section

        new(cask, source, section)
      end

      sig { params(cask: Cask, source: String, section: String).void }
      def initialize(cask, source, section)
        @section = section

        super(cask, source)
      end

      # FIXME: This is a pre-existing violation
      # rubocop:disable Sorbet/AllowIncompatibleOverride
      sig { override(allow_incompatible: true).params(target: T.any(String, Pathname)).returns(Pathname) }
      # rubocop:enable Sorbet/AllowIncompatibleOverride
      def resolve_target(target)
        config.manpagedir.join("man#{section}", target)
      end
    end
  end
end
