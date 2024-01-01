# typed: true
# frozen_string_literal: true

require_relative "tar"

module UnpackStrategy
  # Strategy for unpacking compress archives.
  class Compress < Tar
    sig { returns(T::Array[String]) }
    def self.extensions
      [".Z"]
    end

    def self.can_extract?(path)
      path.magic_number.match?(/\A\037\235/n)
    end
  end
end
