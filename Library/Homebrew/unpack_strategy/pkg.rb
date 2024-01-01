# typed: true
# frozen_string_literal: true

require_relative "uncompressed"

module UnpackStrategy
  # Strategy for unpacking macOS package installers.
  class Pkg < Uncompressed
    sig { returns(T::Array[String]) }
    def self.extensions
      [".pkg", ".mkpg"]
    end

    def self.can_extract?(path)
      path.extname.match?(/\A.m?pkg\Z/) &&
        (path.directory? || path.magic_number.match?(/\Axar!/n))
    end
  end
end
