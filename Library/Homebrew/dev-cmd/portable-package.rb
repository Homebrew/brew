# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "development_tools"
require "dependency"

module Homebrew
  module Cmd
    class PortablePackageCmd < AbstractCommand
      cmd_args do
        usage_banner <<~EOS
          `portable-package` <formulae>

          Build and package portable formulae.
          For internal use in Homebrew taps.
        EOS
        switch "--no-uninstall-deps",
               description: "Don't uninstall all dependencies of portable formulae before testing."
        switch "-v", "--verbose",
               description: "Pass `--verbose` to `brew` commands."
        named_args :formula, min: 1

        hide_from_man_page!
      end

      sig { override.void }
      def run
        ENV["HOMEBREW_DEVELOPER"] = "1"

        verbose = []
        verbose << "--verbose" if args.verbose?
        verbose << "--debug" if args.debug?

        # If test-bot cleanup is performed and auto-updates are disabled, this might not already be installed.
        unless DevelopmentTools.ca_file_handles_most_https_certificates?
          safe_system HOMEBREW_BREW_FILE, "install", "ca-certificates"
        end

        args.named.each do |name|
          name = "portable-#{name}" unless name.start_with? "portable-"
          begin
            # On Linux, install glibc and linux-headers from bottles and don't install their build dependencies.
            bottled_dep_allowlist = /\A(?:glibc|linux-headers)@/
            deps = Dependency.expand(Formula[name], cache_key: "portable-package-#{name}") do |_dependent, dep|
              Dependency.prune if dep.test? || dep.optional?

              next unless bottled_dep_allowlist.match?(dep.name)

              Dependency.keep_but_prune_recursive_deps
            end.map(&:name)

            bottled_deps, deps = deps.partition { |dep| bottled_dep_allowlist.match?(dep) }

            safe_system HOMEBREW_BREW_FILE, "install", *verbose, *bottled_deps if bottled_deps.present?

            # Build bottles for all other dependencies.
            safe_system HOMEBREW_BREW_FILE, "install", "--build-bottle", *verbose, *deps

            safe_system HOMEBREW_BREW_FILE, "install", "--build-bottle", *verbose, name
            unless args.no_uninstall_deps?
              safe_system HOMEBREW_BREW_FILE, "uninstall", "--force", "--ignore-dependencies", *verbose, *deps
            end
            safe_system HOMEBREW_BREW_FILE, "test", *verbose, name
            puts "Linkage information:"
            safe_system HOMEBREW_BREW_FILE, "linkage", *verbose, name
            bottle_args = %w[
              --skip-relocation
              --json
              --no-rebuild
            ]
            safe_system HOMEBREW_BREW_FILE, "bottle", *verbose, *bottle_args, name
          rescue => e
            ofail e
          end
        end
      end
    end
  end
end
