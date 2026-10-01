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

      sig {
        override.params(
          cask:        Cask,
          source:      T.any(String, Pathname),
          target_hash: T.nilable(DirectivesType),
        ).returns(T.attached_class)
      }
      def self.from_args(cask, source, target_hash = nil)
        raise CaskInvalidError.new(cask.token, "No source provided for #{english_name}.") if source.blank?

        if !target_hash.is_a?(Hash) || !target_hash.key?(:target)
          raise CaskInvalidError.new(cask.token, "#{english_name} '#{source}' requires a target.")
        end

        super
      end

      sig { override.params(target: T.any(String, Pathname), base_dir: T.nilable(Pathname)).returns(Pathname) }
      def resolve_target(target, base_dir: nil)
        super
      end
    end
  end
end
