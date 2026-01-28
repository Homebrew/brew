# typed: strict
# frozen_string_literal: true

require_relative "uncompressed"

module UnpackStrategy
  # Strategy for unpacking OpenType fonts.
  class Otf < Uncompressed
    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".otf"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\AOTTO/n)
    end
  end
end
