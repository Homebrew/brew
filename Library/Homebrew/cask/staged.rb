# typed: strict
# frozen_string_literal: true

require "utils/user"
require "utils/output"

module Cask
  # Helper functions for staged casks.
  module Staged
    include ::Utils::Output::Mixin
    extend T::Helpers

    requires_ancestor { ::Cask::DSL::Base }

    Paths = T.type_alias { T.any(String, Pathname, T::Array[T.any(String, Pathname)]) }

    private

    sig { params(paths: Paths).returns(T::Array[Pathname]) }
    def remove_nonexistent(paths)
      Array(paths).map { |p| Pathname(p).expand_path }.select(&:exist?)
    end
  end
end
