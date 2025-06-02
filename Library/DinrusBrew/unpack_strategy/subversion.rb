# typed: strict
# frozen_string_literal: true

require_relative "directory"

module UnpackStrategy
  # Strategy for unpacking Subversion repositories.
  class Subversion < Directory
    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      !!(super && (path/".svn").directory?)
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      system_command! "svn",
                      args:    ["export", "--force", ".", unpack_dir],
                      chdir:   path.to_s,
                      verbose:
    end
  end
end
