# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Generic artifact corresponding to the `artifact` stanza.
    class Artifact < Moved
      sig { override.returns(String) }
      def self.english_name
        "Generic Artifact"
      end

      sig { params(cask: Cask, source: T.nilable(String), target_hash: T.anything).returns(Relocated) }
      def self.from_args(cask, source = nil, **target_hash)
        raise CaskInvalidError.new(cask.token, "No source provided for #{english_name}.") if source.blank?

        unless target_hash.key?(:target)
          raise CaskInvalidError.new(cask.token, "#{english_name} '#{source}' requires a target.")
        end

        new(cask, source, **target_hash)
      end

      # FIXME: This is a pre-existing violation
      # rubocop:disable Sorbet/AllowIncompatibleOverride
      sig { override(allow_incompatible: true).params(target: T.any(String, Pathname)).returns(Pathname) }
      # rubocop:enable Sorbet/AllowIncompatibleOverride
      def resolve_target(target)
        super(target, base_dir: nil)
      end
    end
  end
end
