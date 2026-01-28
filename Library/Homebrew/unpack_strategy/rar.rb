# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking RAR archives.
  class Rar
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".rar"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\ARar!/n)
    end

    sig { returns(T::Array[Formula]) }
    def dependencies
      @dependencies ||= T.let([Formula["libarchive"]], T.nilable(T::Array[Formula]))
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "bsdtar",
                      args:    ["x", "-f", path, "-C", unpack_dir],
                      env:     { "PATH" => PATH.new(Formula["libarchive"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
