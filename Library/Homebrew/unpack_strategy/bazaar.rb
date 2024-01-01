# typed: true
# frozen_string_literal: true

require_relative "directory"

module UnpackStrategy
  # Strategy for unpacking Bazaar archives.
  class Bazaar < Directory
    def self.can_extract?(path)
      super && (path/".bzr").directory?
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      super

      # The export command doesn't work on checkouts (see https://bugs.launchpad.net/bzr/+bug/897511).
      (unpack_dir/".bzr").rmtree
    end
  end
end
