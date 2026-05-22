# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "utils/bottles"
require "utils/portable_ruby"

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
               description: "Do not run `brew vendor-install ruby`; skip the `utils/ruby.sh`, " \
                            "`Gemfile.lock` and RBI updates."

        named_args :none
      end

      sig { override.void }
      def run
        formula = Homebrew.with_no_api_env { Formulary.factory("portable-ruby") }

        version = formula.version.to_s
        pkg_version = formula.pkg_version.to_s
        vendor_dir = Utils::PortableRuby.vendor_dir

        write_file(Utils::PortableRuby.portable_ruby_version_file, "#{pkg_version}\n")
        write_file(Utils::PortableRuby.ruby_version_file, "#{version}\n")

        formula.bottle_specification.checksums.each do |checksum|
          tag_symbol = checksum.fetch("tag")
          tag = Utils::Bottles::Tag.from_symbol(tag_symbol)
          os = tag.linux? ? "linux" : "darwin"
          path = vendor_dir/"portable-ruby-#{tag.standardized_arch}-#{os}"
          write_file(path, "ruby_TAG=#{tag_symbol}\nruby_SHA=#{checksum.fetch("digest")}\n")
        end

        return if args.skip_vendor_install?

        ohai "brew vendor-install ruby"
        safe_system HOMEBREW_BREW_FILE, "vendor-install", "ruby" unless args.dry_run?

        Utils::PortableRuby.refresh_vendored_gems_and_rbis!(pkg_version:, dry_run: args.dry_run?)
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
