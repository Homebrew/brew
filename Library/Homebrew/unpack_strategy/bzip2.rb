# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking bzip2 archives.
  class Bzip2
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".bz2"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\ABZh/n)
    end

    sig { returns(T::Array[Formula]) }
    def dependencies
      @dependencies ||= T.let([Formula["bzip2"]], T.nilable(T::Array[Formula]))
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      FileUtils.cp path, unpack_dir/basename, preserve: true
      quiet_flags = verbose ? [] : ["-q"]
      system_command! "bunzip2",
                      args:    [*quiet_flags, unpack_dir/basename],
                      env:     { "PATH" => PATH.new(Formula["bzip2"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
