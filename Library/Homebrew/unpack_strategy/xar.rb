# typed: true
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking xar archives.
  class Xar
    include UnpackStrategy

    sig { returns(T::Array[String]) }
    def self.extensions
      [".xar"]
    end

    def self.can_extract?(path)
      path.magic_number.match?(/\Axar!/n)
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "xar",
                      args:    ["-x", "-f", path, "-C", unpack_dir],
                      verbose:
    end
  end
end
