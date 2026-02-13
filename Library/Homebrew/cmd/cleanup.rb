# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cleanup"
require "formula"
require "utils"

module Homebrew
  module Cmd
    class CleanupCmd < AbstractCommand
      cmd_args do
        days = Homebrew::EnvConfig::ENVS[:HOMEBREW_CLEANUP_MAX_AGE_DAYS]&.dig(:default)
        description <<~EOS
          Remove stale lock files and outdated downloads for all formulae and casks,
          and remove old versions of installed formulae. If arguments are specified,
          only do this for the given formulae and casks. Removes all downloads more than
          #{days} days old. This can be adjusted with `$HOMEBREW_CLEANUP_MAX_AGE_DAYS`.
        EOS
        flag   "--prune=",
               description: "Remove all cache files older than specified <days>. " \
                            "If you want to remove everything, use `--prune=all`."
        switch "-n", "--dry-run",
               description: "Show what would be removed, but do not actually remove anything."
        switch "-s", "--scrub",
               description: "Scrub the cache, including downloads for even the latest versions. " \
                            "Note that downloads for any installed formulae or casks will still not be deleted. " \
                            "If you want to delete those too: `rm -rf \"$(brew --cache)\"`"
        switch "--prune-prefix",
               description: "Only prune the symlinks and directories from the prefix and remove no other files."

        named_args [:formula, :cask]
      end

      # compatible with non-standard Formula instances, filtering invalid dependencies.
      sig { returns(T::Set[Formula]) }
      def self.required_formulae
        # Only standard installed Formula instances are used(exclude NamespaceAPI)
        installed_formulae = Formula.installed.grep(Formula)
        return Set.new if installed_formulae.empty?

        required = Set.new

        # Collect direct runtime dependencies and reverse dependencies
        installed_formulae.each do |f|
          required.add(f)
          f.runtime_dependencies.each do |dep|
            next if dep.to_formula.nil? # Skip invalid dependencies

            dep_formula = dep.to_formula
            # Only standard Formula instances are processed + already installed.
            next if !dep_formula.is_a?(Formula) || !dep_formula.any_version_installed?

            required.add(dep_formula)
          rescue
            # If a dependency resolution exception (such as the NamespaceAPI class) is caught, skip it directly.
            next
          end

          next if required.include?(f)

          begin
            # The `brew uses` function looks up installed reverse dependencies.
            reverse_deps = Utils.safe_popen_read(
              "brew", "uses", "--installed", "--recursive", f.name
            ).lines(chomp: true).filter_map do |name|
              formula = begin
                Formula[name]
              rescue
                nil
              end
              # Only keep standard Formula instances + already installed
              formula if formula.is_a?(Formula) && formula.any_version_installed?
            end
            required.merge(reverse_deps) unless reverse_deps.empty?
          rescue
            # Catching reverse dependency lookup exceptions and skipping the current formula.
            next
          end
        end

        required
      end

      sig { override.void }
      def run
        days = args.prune.presence&.then do |prune|
          case prune
          when /\A\d+\Z/
            prune.to_i
          when "all"
            0
          else
            raise UsageError, "`--prune` expects an integer or `all`."
          end
        end

        # Fix the hook cleanup instance
        cleanup = Cleanup.new(*args.named, dry_run: args.dry_run?, scrub: args.s?, days:)
        # Get the formulaes that needed to be kept
        required_formulae = self.class.required_formulae
        # overwrite the moethod
        cleanup.define_singleton_method(:installed_formulae) do
          super().grep(Formula) - required_formulae
        end
        # ========== Hook end ==========

        if args.prune_prefix?
          cleanup.prune_prefix_symlinks_and_directories
          return
        end

        cleanup.clean!(quiet: args.quiet?, periodic: false)

        unless cleanup.disk_cleanup_size.zero?
          disk_space = Formatter.disk_usage_readable(cleanup.disk_cleanup_size)
          if args.dry_run?
            ohai "This operation would free approximately #{disk_space} of disk space."
          else
            ohai "This operation has freed approximately #{disk_space} of disk space."
          end
        end

        return if cleanup.unremovable_kegs.empty?

        ofail <<~EOS
          Could not cleanup old kegs! Fix your permissions on:
            #{cleanup.unremovable_kegs.join "\n  "}
        EOS
      end
    end
  end
end
