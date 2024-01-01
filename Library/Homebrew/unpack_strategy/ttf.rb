# typed: true
# frozen_string_literal: true

require_relative "uncompressed"

module UnpackStrategy
  # Strategy for unpacking TrueType fonts.
  class Ttf < Uncompressed
    sig { returns(T::Array[String]) }
    def self.extensions
      [".ttc", ".ttf"]
    end

    def self.can_extract?(path)
      # TrueType Font
      path.magic_number.match?(/\A\000\001\000\000\000/n) ||
        # Truetype Font Collection
        path.magic_number.match?(/\Attcf/n)
    end
  end
end
