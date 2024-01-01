# typed: true
# frozen_string_literal: true

require_relative "generic_unar"

module UnpackStrategy
  # Strategy for unpacking Stuffit archives.
  class Sit < GenericUnar
    sig { returns(T::Array[String]) }
    def self.extensions
      [".sit"]
    end

    def self.can_extract?(path)
      path.magic_number.match?(/\AStuffIt/n)
    end
  end
end
