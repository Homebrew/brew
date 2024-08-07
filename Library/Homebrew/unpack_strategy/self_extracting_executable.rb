# typed: strict
# frozen_string_literal: true

require_relative "generic_unar"

module UnpackStrategy
  # Strategy for unpacking self-extracting executables.
  class SelfExtractingExecutable < GenericUnar
    sig { override.returns(T::Array[String]) }
    def self.extensions
      []
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\AMZ/n) &&
        path.file_type.include?("self-extracting archive")
    end
  end
end
