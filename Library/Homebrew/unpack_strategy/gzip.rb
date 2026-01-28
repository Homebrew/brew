# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking gzip archives.
  class Gzip
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".gz"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\A\037\213/n)
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      FileUtils.cp path, unpack_dir/basename, preserve: true
      quiet_flags = verbose ? [] : ["-q"]
      system_command! "gunzip",
                      args:    [*quiet_flags, "-N", "--", unpack_dir/basename],
                      verbose:
    end
  end
end
