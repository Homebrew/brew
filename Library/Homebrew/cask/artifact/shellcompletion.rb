# typed: strict
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    class ShellCompletion < Symlinked
      sig { params(cask: Cask, source: T.any(String, Pathname)).returns(ShellCompletion) }
      def self.from_args(cask, source)
        new(cask, source)
      end

      sig { params(_: T.any(String, Pathname)).returns(Pathname) }
      def resolve_target(_)
        raise CaskInvalidError, "Shell completion without shell info"
      end
    end
  end
end
