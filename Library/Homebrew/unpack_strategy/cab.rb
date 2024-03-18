# typed: true
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking Cabinet archives.
  class Cab
    include UnpackStrategy

    sig { returns(T::Array[String]) }
    def self.extensions
      [".cab"]
    end

    def self.can_extract?(path)
      path.magic_number.match?(/\AMSCF/n)
    end

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "cabextract",
                      args:    ["-d", unpack_dir, "--", path],
                      env:     { "PATH" => PATH.new(Formula["cabextract"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end

    def dependencies
      @dependencies ||= [Formula["cabextract"]]
    end
  end
end
