# typed: true
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking xz archives.
  class Xz
    include UnpackStrategy

    sig { returns(T::Array[String]) }
    def self.extensions
      [".xz"]
    end

    def self.can_extract?(path)
      path.magic_number.match?(/\A\xFD7zXZ\x00/n)
    end

    def dependencies
      @dependencies ||= [Formula["xz"]]
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      FileUtils.cp path, unpack_dir/basename, preserve: true
      quiet_flags = verbose ? [] : ["-q"]
      system_command! "unxz",
                      args:    [*quiet_flags, "-T0", "--", unpack_dir/basename],
                      env:     { "PATH" => PATH.new(Formula["xz"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
