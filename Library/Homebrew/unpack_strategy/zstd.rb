# typed: true
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking zstd archives.
  class Zstd
    include UnpackStrategy

    sig { returns(T::Array[String]) }
    def self.extensions
      [".zst"]
    end

    def self.can_extract?(path)
      path.magic_number.match?(/\x28\xB5\x2F\xFD/n)
    end

    def dependencies
      @dependencies ||= [Formula["zstd"]]
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      FileUtils.cp path, unpack_dir/basename, preserve: true
      quiet_flags = verbose ? [] : ["-q"]
      system_command! "unzstd",
                      args:    [*quiet_flags, "-T0", "--rm", "--", unpack_dir/basename],
                      env:     { "PATH" => PATH.new(Formula["zstd"].opt_bin, ENV.fetch("PATH")) },
                      verbose: verbose
    end
  end
end
