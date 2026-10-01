# typed: strict
# frozen_string_literal: true

require "api/env"
require "utils/brew_command"

require "abstract_command"
require "formula"
require "utils/bottles"
require "utils/portable_ruby"

module Homebrew
  module DevCmd
    class UpdatePortableRuby < AbstractCommand
      cmd_args do
        description <<~EOS
          Update the vendored `portable-ruby` from the current `portable-ruby` formula:
          write the version files and bottle checksums, run `brew vendor-install ruby`,
          then sync `utils/ruby.sh`, vendored gems and RBI files to the bundler shipped
          by the new ruby.
        EOS
        switch "--print-target-version",
               description: "Print the target portable Ruby package version without updating it."
        named_args :none

        hide_from_man_page!
      end

      sig { override.void }
      def run
        formula = Homebrew::API.with_no_api_env { Formulary.factory("portable-ruby") }
        pkg_version = formula.pkg_version.to_s
        if args.print_target_version?
          puts pkg_version
          return
        end

        vendor_dir = HOMEBREW_LIBRARY_PATH/"vendor"

        (vendor_dir/"portable-ruby-version").atomic_write("#{pkg_version}\n")
        (HOMEBREW_LIBRARY_PATH/".ruby-version").atomic_write("#{formula.version}\n")

        formula.bottle_specification.checksums.each do |checksum|
          tag_symbol = checksum.fetch("tag")
          tag = Utils::Bottles::Tag.from_symbol(tag_symbol)
          os = tag.linux? ? "linux" : "darwin"
          path = vendor_dir/"portable-ruby-#{tag.standardized_arch}-#{os}"
          path.atomic_write("ruby_TAG=#{tag_symbol}\nruby_SHA=#{checksum.fetch("digest")}\n")
        end

        Utils::BrewCommand.run! "vendor-install", "ruby"

        bundler_version = Utils::PortableRuby.sync_bundler_version!(pkg_version)
        Utils::BrewCommand.run! "vendor-gems", "--no-commit",
                                "--update=--ruby,--bundler=#{bundler_version}"
        Utils::BrewCommand.run! "typecheck", "--update"
      end
    end
  end
end
