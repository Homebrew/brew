# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "bundler"
require "formula"
require "utils/bottles"

module Homebrew
  module DevCmd
    class UpdatePortableRuby < AbstractCommand
      cmd_args do
        description <<~EOS
          Update the vendored portable Ruby version files, bottle checksums,
          `utils/ruby.sh` and `Gemfile.lock` entries from the current
          `portable-ruby` formula.
        EOS
        switch "-n", "--dry-run",
               description: "Print what would be done rather than doing it."
        switch "--skip-vendor-install",
               description: "Do not run `brew vendor-install ruby`; skip the `utils/ruby.sh` and " \
                            "`Gemfile.lock` updates."

        named_args :none
      end

      sig { params(contents: String, ruby_version: String, bundler_version: String).returns(T::Boolean) }
      def self.lockfile_in_sync?(contents, ruby_version, bundler_version)
        parsed = Bundler::LockfileParser.new(contents)
        parsed.ruby_version == "ruby #{ruby_version}" &&
          parsed.bundler_version&.to_s == bundler_version
      end

      sig { override.void }
      def run
        formula = Homebrew.with_no_api_env { Formulary.factory("portable-ruby") }

        version = formula.version.to_s
        pkg_version = formula.pkg_version.to_s
        vendor_dir = HOMEBREW_LIBRARY_PATH/"vendor"

        write_file(vendor_dir/"portable-ruby-version", "#{pkg_version}\n")
        write_file(HOMEBREW_LIBRARY_PATH/".ruby-version", "#{version}\n")

        formula.bottle_specification.checksums.each do |checksum|
          tag_symbol = checksum.fetch("tag")
          tag = Utils::Bottles::Tag.from_symbol(tag_symbol)
          os = tag.linux? ? "linux" : "darwin"
          path = vendor_dir/"portable-ruby-#{tag.standardized_arch}-#{os}"
          write_file(path, "ruby_TAG=#{tag_symbol}\nruby_SHA=#{checksum.fetch("digest")}\n")
        end

        return if args.skip_vendor_install?

        if args.dry_run?
          ohai "brew vendor-install ruby"
          ohai "Would update #{HOMEBREW_LIBRARY_PATH/"utils/ruby.sh"} and #{HOMEBREW_LIBRARY_PATH/"Gemfile.lock"} " \
               "with the bundler version shipped by portable-ruby #{pkg_version}."
          return
        end

        ohai "brew vendor-install ruby"
        safe_system HOMEBREW_BREW_FILE, "vendor-install", "ruby"

        bundler_dir = Pathname.glob(vendor_dir/"portable-ruby/#{pkg_version}/lib/ruby/gems/*/gems/bundler-*").first
        odie "Cannot find vendored bundler for portable-ruby #{pkg_version}." if bundler_dir.nil?
        bundler_version = bundler_dir.basename.to_s.delete_prefix("bundler-")

        ruby_sh = HOMEBREW_LIBRARY_PATH/"utils/ruby.sh"
        original = ruby_sh.read
        updated = original.sub(/(?<=^export HOMEBREW_BUNDLER_VERSION=")[^"]+/, bundler_version)
        if original != updated
          ohai "Writing #{ruby_sh}"
          ruby_sh.atomic_write(updated)
        end

        gemfile_lock = (HOMEBREW_LIBRARY_PATH/"Gemfile.lock").read
        return if self.class.lockfile_in_sync?(gemfile_lock, version, bundler_version)

        ohai "brew vendor-gems --no-commit --update=--ruby,--bundler=#{bundler_version}"
        safe_system HOMEBREW_BREW_FILE, "vendor-gems", "--no-commit", "--update=--ruby,--bundler=#{bundler_version}"
      end

      private

      sig { params(path: Pathname, contents: String).void }
      def write_file(path, contents)
        if args.dry_run?
          ohai "Write #{path}:"
          puts contents
        else
          ohai "Writing #{path}"
          path.atomic_write(contents)
        end
      end
    end
  end
end
