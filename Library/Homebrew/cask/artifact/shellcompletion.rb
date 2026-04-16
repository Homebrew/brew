# typed: strict
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    class ShellCompletion < Symlinked
      sig { override.overridable.params(_: T.any(String, Pathname), base_dir: T.nilable(Pathname)).returns(Pathname) }
      def resolve_target(_, base_dir: nil)
        raise CaskInvalidError, "Shell completion without shell info"
      end
    end
  end
end
