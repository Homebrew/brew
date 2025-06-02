# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking zstd archives.
  class Zstd
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".zst"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\x28\xB5\x2F\xFD/n)
    end

    sig { returns(T::Array[Formula]) }
    def dependencies
      @dependencies ||= T.let([Formula["zstd"]], T.nilable(T::Array[Formula]))
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      FileUtils.cp path, unpack_dir/basename, preserve: true
      quiet_flags = verbose ? [] : ["-q"]
      system_command! "unzstd",
                      args:    [*quiet_flags, "-T0", "--rm", "--", unpack_dir/basename],
                      env:     { "PATH" => PATH.new(Formula["zstd"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
