# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking pax archives.
  class Pax
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".pax"]
    end

    sig { override.params(_path: Pathname).returns(T::Boolean) }
    def self.can_extract?(_path)
      false
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "pax",
                      args:    ["-rf", path],
                      chdir:   unpack_dir,
                      verbose:
    end
  end
end
