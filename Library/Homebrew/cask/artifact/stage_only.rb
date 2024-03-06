# typed: true
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"

module Cask
  module Artifact
    # Artifact corresponding to the `stage_only` stanza.
    class StageOnly < AbstractArtifact
      def self.from_args(cask, *args, **kwargs)
        if (args != [true] && args != ["true"]) || kwargs.present?
          raise CaskInvalidError.new(cask.token, "'stage_only' takes only a single argument: true")
        end

        new(cask, true)
      end

      sig { returns(T::Array[T::Boolean]) }
      def to_a
        [true]
      end

      sig { override.returns(String) }
      def summarize
        "true"
      end
    end
  end
end
