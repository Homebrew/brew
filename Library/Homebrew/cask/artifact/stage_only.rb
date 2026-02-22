# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"

module Cask
  module Artifact
    # Artifact corresponding to the `stage_only` stanza.
    class StageOnly < AbstractArtifact
      sig { params(cask: Cask, arg: T.any(String, TrueClass)).returns(StageOnly) }
      def self.from_args(cask, arg)
        unless [true, "true"].include?(arg)
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
