# typed: true
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking lzip archives.
  class Lzip
    include UnpackStrategy

    sig { returns(T::Array[String]) }
    def self.extensions
      [".lz"]
    end

    def self.can_extract?(path)
      path.magic_number.match?(/\ALZIP/n)
    end

    def dependencies
      @dependencies ||= [Formula["lzip"]]
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      FileUtils.cp path, unpack_dir/basename, preserve: true
      quiet_flags = verbose ? [] : ["-q"]
      system_command! "lzip",
                      args:    ["-d", *quiet_flags, unpack_dir/basename],
                      env:     { "PATH" => PATH.new(Formula["lzip"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
