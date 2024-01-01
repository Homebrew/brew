# typed: true
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking RAR archives.
  class Rar
    include UnpackStrategy

    sig { returns(T::Array[String]) }
    def self.extensions
      [".rar"]
    end

    def self.can_extract?(path)
      path.magic_number.match?(/\ARar!/n)
    end

    def dependencies
      @dependencies ||= [Formula["libarchive"]]
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "bsdtar",
                      args:    ["x", "-f", path, "-C", unpack_dir],
                      env:     { "PATH" => PATH.new(Formula["libarchive"].opt_bin, ENV.fetch("PATH")) },
                      verbose: verbose
    end
  end
end
