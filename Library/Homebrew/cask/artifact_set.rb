# typed: strict
# frozen_string_literal: true

module Cask
  # Sorted set containing all cask artifacts.
  class ArtifactSet < ::Set
    extend T::Generic

    Elem = type_member(:out) { { fixed: Artifact::AbstractArtifact } }

    sig { params(block: T.nilable(T.proc.params(arg0: Elem).returns(T.untyped))).void }
    def each(&block)
      return enum_for(T.must(__method__)) { size } unless block

      to_a.each(&block)
      self
    end

    sig { returns(T::Array[Artifact::AbstractArtifact]) }
    def to_a
      super.sort
    end
  end
end
