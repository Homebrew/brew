# typed: strict
# frozen_string_literal: true

require_relative "uncompressed"

module UnpackStrategy
  # Strategy for unpacking executables.
  class Executable < Uncompressed
    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".sh", ".bash"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\A#!\s*\S+/n) ||
        path.magic_number.match?(/\AMZ/n)
    end
  end
end
