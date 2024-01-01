# typed: true
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking archives with `unar`.
  class GenericUnar
    include UnpackStrategy

    sig { returns(T::Array[String]) }
    def self.extensions
      []
    end

    def self.can_extract?(_path)
      false
    end

    def dependencies
      @dependencies ||= [Formula["unar"]]
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "unar",
                      args:    [
                        "-force-overwrite", "-quiet", "-no-directory",
                        "-output-directory", unpack_dir, "--", path
                      ],
                      env:     { "PATH" => PATH.new(Formula["unar"].opt_bin, ENV.fetch("PATH")) },
                      verbose: verbose
    end
  end
end
