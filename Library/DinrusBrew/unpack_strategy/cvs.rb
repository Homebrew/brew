# typed: strict
# frozen_string_literal: true

require_relative "directory"

module UnpackStrategy
  # Strategy for unpacking CVS repositories.
  class Cvs < Directory
    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      !!(super && (path/"CVS").directory?)
    end
  end
end
