# typed: strict
# frozen_string_literal: true

require "utils/output"

module Utils
  # Helper functions for the vendored portable-ruby.
  module PortableRuby
    extend Utils::Output::Mixin

    # Syncs `HOMEBREW_BUNDLER_VERSION` in `utils/ruby.sh` with the bundler shipped
    # by the portable-ruby unpacked at `pkg_version`.
    sig { params(pkg_version: String).returns(String) }
    def self.sync_bundler_version!(pkg_version)
      unpacked = HOMEBREW_LIBRARY_PATH/"vendor/portable-ruby/#{pkg_version}"
      bundler_dir = Pathname.glob(unpacked/"lib/ruby/gems/*/gems/bundler-*").first
      odie "Cannot find vendored bundler for portable-ruby #{pkg_version}." if bundler_dir.nil?

      bundler_version = bundler_dir.basename.to_s.delete_prefix("bundler-")

      ruby_sh = HOMEBREW_LIBRARY_PATH/"utils/ruby.sh"
      original = ruby_sh.read
      updated = original.sub(/(?<=^export HOMEBREW_BUNDLER_VERSION=")[^"]+/, bundler_version)
      ruby_sh.atomic_write(updated) if original != updated

      bundler_version
    end
  end
end
