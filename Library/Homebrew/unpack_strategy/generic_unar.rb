# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking archives with `unar`.
  class GenericUnar
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      []
    end

    sig { override.params(_path: Pathname).returns(T::Boolean) }
    def self.can_extract?(_path)
      false
    end

    sig { returns(T::Array[Formula]) }
    def dependencies
      @dependencies ||= T.let([Formula["unar"]], T.nilable(T::Array[Formula]))
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "unar",
                      args:    [
                        "-force-overwrite", "-quiet", "-no-directory",
                        "-output-directory", unpack_dir, "--", path
                      ],
                      env:     { "PATH" => PATH.new(Formula["unar"].opt_bin, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
