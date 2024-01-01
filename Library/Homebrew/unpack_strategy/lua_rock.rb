# typed: true
# frozen_string_literal: true

require_relative "uncompressed"

module UnpackStrategy
  # Strategy for unpacking LuaRock archives.
  class LuaRock < Uncompressed
    sig { returns(T::Array[String]) }
    def self.extensions
      [".rock"]
    end

    def self.can_extract?(path)
      return false unless Zip.can_extract?(path)

      # Check further if the ZIP is a LuaRocks package.
      path.zipinfo.grep(%r{\A[^/]+.rockspec\Z}).any?
    end
  end
end
