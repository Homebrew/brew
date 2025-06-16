# typed: strict
# frozen_string_literal: true

require_relative "generic_unar"

module UnpackStrategy
  # Strategy for unpacking Stuffit archives.
  class Sit < GenericUnar
    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".sit"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\AStuffIt/n)
    end
  end
end
