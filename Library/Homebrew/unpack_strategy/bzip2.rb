# typed: strict
# frozen_string_literal: true

module UnpackStrategy
  # Strategy for unpacking bzip2 archives.
  class Bzip2
    include UnpackStrategy

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [".bz2"]
    end

    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      path.magic_number.match?(/\ABZh/n)
    end

    sig { returns(T::Array[Pathname]) }
    def self.bzip2_paths
      # Integration tests rewrite the HOMEBREW_PREFIX constant, so use exported startup paths for the real prefix.
      original_repository = Pathname(ENV.fetch("HOMEBREW_REPOSITORY"))
      original_prefix = if original_repository.basename.to_s == "Homebrew"
        original_repository.dirname
      else
        Pathname(ENV.fetch("HOMEBREW_PREFIX"))
      end

      [HOMEBREW_PREFIX/"opt/bzip2/bin", original_prefix/"opt/bzip2/bin"].uniq
    end

    sig { returns(T::Array[Formula]) }
    def dependencies
      @dependencies ||= T.let([Formula["bzip2"]], T.nilable(T::Array[Formula]))
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      FileUtils.cp path, unpack_dir/basename, preserve: true
      quiet_flags = verbose ? [] : ["-q"]
      system_command! "bunzip2",
                      args:    [*quiet_flags, unpack_dir/basename],
                      env:     { "PATH" => PATH.new(self.class.bzip2_paths, ORIGINAL_PATHS, ENV.fetch("PATH")) },
                      verbose:
    end
  end
end
