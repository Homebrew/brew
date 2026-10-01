# typed: true
# frozen_string_literal: true

module Test
  module Helper
    module Fixtures
      def dylib_path(name)
        MachOPathname.wrap("#{TEST_FIXTURE_DIR}/mach/#{name}.dylib")
      end

      def bundle_path(name)
        MachOPathname.wrap("#{TEST_FIXTURE_DIR}/mach/#{name}.bundle")
      end

      def cask_path(name)
        fixture("cask/Casks/#{name}.rb")
      end

      def tarball_fixture(name)
        fixture("tarballs/#{name}")
      end

      def tarball_fixture_sha256(name)
        sha256_for_fixture_path(tarball_fixture(name))
      end

      def patch_fixture(name)
        fixture("patches/#{name}.diff")
      end

      def patch_fixture_sha256(name)
        sha256_for_fixture_path(patch_fixture(name))
      end

      def fixture(name)
        TEST_FIXTURE_DIR/name
      end

      private

      # Intentionally wanting to cache this globally as fixtures are immutable.
      # rubocop:disable Style/ClassVars
      @@fixture_sha256 = {}
      # rubocop:enable Style/ClassVars
      def sha256_for_fixture_path(path)
        @@fixture_sha256[path] ||= Digest::SHA256.file(path).hexdigest
      end
    end
  end
end
