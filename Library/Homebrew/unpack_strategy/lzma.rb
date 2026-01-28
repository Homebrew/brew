# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking LZMA archives.
  class Lzma
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".lzma"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\A\]\000\000\200\000/n)
    end

    sig { returns(T::Array[Formula]) }
    def dependencies
      @dependencies ||= T.let([Formula["xz"]], T.nilable(T::Array[Formula]))
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      FileUtils.cp path, unpack_dir/basename, preserve: true
      quiet_flags = verbose ? [] : ["-q"]
      system_command! "unlzma",
                      args:    [*quiet_flags, "--", unpack_dir/basename],
                      env:     { "PATH" => PATH.new(Formula["xz"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
