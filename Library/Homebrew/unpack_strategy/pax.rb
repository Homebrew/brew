# typed: true
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking pax archives.
  class Pax
    include UnpackStrategy

    sig { returns(T::Array[String]) }
    def self.extensions
      [".pax"]
    end

    def self.can_extract?(_path)
      false
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "pax",
                      args:    ["-rf", path],
                      chdir:   unpack_dir,
                      verbose: verbose
    end
  end
end
