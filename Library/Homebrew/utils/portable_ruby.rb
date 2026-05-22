# typed: strict
# frozen_string_literal: true

module Utils
  # Helper functions for the vendored portable-ruby.
  module PortableRuby
    extend Utils::Output::Mixin

    sig { returns(Pathname) }
    def self.vendor_dir
      HOMEBREW_LIBRARY_PATH/"vendor"
    end

    sig { returns(Pathname) }
    def self.ruby_version_file
      HOMEBREW_LIBRARY_PATH/".ruby-version"
    end

    sig { returns(Pathname) }
    def self.utils_ruby_sh
      HOMEBREW_LIBRARY_PATH/"utils/ruby.sh"
    end

    sig { returns(Pathname) }
    def self.portable_ruby_version_file
      vendor_dir/"portable-ruby-version"
    end

    sig { params(pkg_version: String).returns(Pathname) }
    def self.unpacked_ruby_dir(pkg_version)
      vendor_dir/"portable-ruby/#{pkg_version}"
    end

    sig { params(pkg_version: String).returns(String) }
    def self.bundler_version_for(pkg_version)
      bundler_dir = Pathname.glob(unpacked_ruby_dir(pkg_version)/"lib/ruby/gems/*/gems/bundler-*").first
      odie "Cannot find vendored bundler for portable-ruby #{pkg_version}." if bundler_dir.nil?

      bundler_dir.basename.to_s.delete_prefix("bundler-")
    end

    sig { params(bundler_version: String, dry_run: T::Boolean).void }
    def self.update_bundler_version!(bundler_version, dry_run:)
      original = utils_ruby_sh.read
      updated = original.sub(/(?<=^export HOMEBREW_BUNDLER_VERSION=")[^"]+/, bundler_version)
      return if original == updated

      if dry_run
        ohai "Would update HOMEBREW_BUNDLER_VERSION in #{utils_ruby_sh} to #{bundler_version}."
      else
        ohai "Writing #{utils_ruby_sh}"
        utils_ruby_sh.atomic_write(updated)
      end
    end

    sig { params(pkg_version: String, dry_run: T::Boolean).void }
    def self.refresh_vendored_gems_and_rbis!(pkg_version:, dry_run:)
      if dry_run
        ohai "Would update HOMEBREW_BUNDLER_VERSION in #{utils_ruby_sh} from the bundler " \
             "shipped by portable-ruby #{pkg_version}."
        ohai "brew vendor-gems --no-commit --update=--ruby,--bundler=<new>"
        ohai "brew typecheck --update"
        return
      end

      bundler_version = bundler_version_for(pkg_version)
      update_bundler_version!(bundler_version, dry_run: false)

      ohai "brew vendor-gems --no-commit --update=--ruby,--bundler=#{bundler_version}"
      safe_system HOMEBREW_BREW_FILE, "vendor-gems", "--no-commit", "--update=--ruby,--bundler=#{bundler_version}"

      ohai "brew typecheck --update"
      safe_system HOMEBREW_BREW_FILE, "typecheck", "--update"
    end
  end
end
