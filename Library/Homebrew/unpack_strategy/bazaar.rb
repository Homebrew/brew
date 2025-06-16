# typed: strict
# frozen_string_literal: true

require_relative "directory"

module UnpackStrategy
  # Strategy for unpacking Bazaar archives.
  class Bazaar < Directory
    sig { override.params(path: Pathname).returns(T::Boolean) }
    def self.can_extract?(path)
      !!(super && (path/".bzr").directory?)
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      super

      # The export command doesn't work on checkouts (see https://bugs.launchpad.net/bzr/+bug/897511).
      FileUtils.rm_r(unpack_dir/".bzr")
    end
  end
end
