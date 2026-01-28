# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking P7ZIP archives.
  class P7Zip
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".7z"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\A7z\xBC\xAF\x27\x1C/n)
    end

    sig { returns(T::Array[Formula]) }
    def dependencies
      @dependencies ||= T.let([Formula["p7zip"]], T.nilable(T::Array[Formula]))
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "7zr",
                      args:    ["x", "-y", "-bd", "-bso0", path, "-o#{unpack_dir}"],
                      env:     { "PATH" => PATH.new(Formula["p7zip"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
