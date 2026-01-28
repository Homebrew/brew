# typed: strict
# frozen_string_literal: true

require_relative "uncompressed"

module UnpackStrategy
  # Strategy for unpacking macOS package installers.
  class Pkg < Uncompressed
    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".pkg", ".mkpg"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.extname.match?(/\A.m?pkg\Z/) &&
        (path.directory? || path.magic_number.match?(/\Axar!/n))
    end
  end
end
