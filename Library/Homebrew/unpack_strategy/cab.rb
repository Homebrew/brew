# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking Cabinet archives.
  class Cab
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".cab"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\AMSCF/n)
    end

    sig { returns(T::Array[Formula]) }
    def dependencies
      @dependencies ||= T.let([Formula["cabextract"]], T.nilable(T::Array[Formula]))
    end

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "cabextract",
                      args:    ["-d", unpack_dir, "--", path],
                      env:     { "PATH" => PATH.new(Formula["cabextract"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
