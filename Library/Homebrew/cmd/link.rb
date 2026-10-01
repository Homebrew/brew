# typed: strict
# frozen_string_literal: true

require "utils/shell"

require "abstract_command"
require "caveats"
require "unlink"

module Homebrew
  module Cmd
    class Link < AbstractCommand
      cmd_args do
        description <<~EOS
          Symlink all of <formula>'s installed files or <cask>'s binaries, manpages
          and shell completions into Homebrew's prefix. This is done automatically
          when you install formulae and casks but can be useful for manual
          installations.
        EOS
        switch "--overwrite",
               description: "Delete files that already exist in the prefix while linking."
        switch "-n", "--dry-run",
               description: "List files which would be linked or deleted by " \
                            "`brew link --overwrite` without actually linking or deleting any files."
        switch "-f", "--force",
               description: "Allow keg-only formulae to be linked. When linking casks, overwrite " \
                            "existing symlinks originally from the same cask."
        switch "--HEAD",
               description: "Link the HEAD version of the formula if it is installed."
        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."

        conflicts "--formula", "--cask"
        conflicts "--HEAD", "--cask"

        named_args [:installed_formula, :installed_cask], min: 1
      end

      sig { override.void }
      def run
        kegs, casks = if args.HEAD?
          args.named.to_kegs_to_casks(only: :formula, method: :kegs)
        else
          args.named.to_kegs_to_casks(method: :latest_kegs)
        end
        if args.HEAD?
          kegs = kegs.group_by(&:name).filter_map do |name, resolved_kegs|
            head_keg = resolved_kegs.find { |keg| keg.version.head? }
            next head_keg if head_keg.present?

            opoo <<~EOS
              No HEAD keg installed for #{name}
              To install, run:
                brew install --HEAD #{name}
            EOS

            nil
          end
        end

        kegs.freeze.each do |keg|
          keg_only = Formulary.keg_only?(keg.rack)
          formula = begin
            keg.to_formula
          rescue FormulaUnavailableError
            # Not all kegs may belong to current formulae
            nil
          end
          versioned_keg_only_formula = formula.present? && formula.keg_only_reason&.versioned_formula?

          if keg.linked?
            opoo "Already linked: #{keg}"
            name_and_flag = +""
            name_and_flag << "--HEAD " if args.HEAD?
            name_and_flag << "--force " if keg_only && !versioned_keg_only_formula
            name_and_flag << keg.name
            puts <<~EOS
              To relink, run:
                brew unlink #{keg.name} && brew link #{name_and_flag}
            EOS
            next
          end

          if args.dry_run?
            if args.overwrite?
              puts "Would remove:"
            else
              puts "Would link:"
            end
            keg.link(overwrite: args.overwrite?, dry_run: args.dry_run?, verbose: args.verbose?)
            puts_keg_only_path_message(keg) if keg_only && !versioned_keg_only_formula
            next
          end

          if keg_only
            if HOMEBREW_PREFIX.to_s == HOMEBREW_DEFAULT_PREFIX && formula.present? &&
               formula.keg_only_reason.by_macos?
              caveats = Caveats.new(formula)
              opoo <<~EOS
                Refusing to link macOS provided/shadowed software: #{keg.name}
                #{caveats.keg_only_text(skip_reason: true)&.strip}
              EOS
              next
            end

            if !args.force? && (formula.nil? || !formula.keg_only_reason.versioned_formula?)
              opoo "#{keg.name} is keg-only and must be linked with `--force`."
              puts_keg_only_path_message(keg)
              next
            end
          end

          Unlink.unlink_link_overwrite_formulae(formula, verbose: args.verbose?) if formula

          keg.lock do
            print "Linking #{keg}... "
            puts if args.verbose?

            begin
              n = keg.link(overwrite: args.overwrite?, dry_run: args.dry_run?, verbose: args.verbose?)
            rescue Keg::LinkError
              puts
              raise
            else
              puts "#{n} symlinks created."
            end

            if keg_only && !versioned_keg_only_formula && !Homebrew::EnvConfig.developer?
              puts_keg_only_path_message(keg)
            end
          end
        end

        casks.each do |cask|
          raise Cask::CaskNotInstalledError, cask unless cask.installed?

          artifacts = cask.artifacts.grep(Cask::Artifact::Symlinked)
          conflict = artifacts.find do |artifact|
            artifact.link_action(force: args.force?, overwrite: args.overwrite?) == :conflict
          end
          if conflict
            raise Cask::CaskError, <<~EOS
              Could not link #{cask}: #{conflict.target} already exists.
              To force the link and overwrite all conflicting files:
                brew link --cask --overwrite #{cask}
            EOS
          end

          puts(args.overwrite? ? "Would remove:" : "Would link:") if args.dry_run?
          artifacts.each do |artifact|
            artifact.install_phase(force: args.force?, overwrite: args.overwrite?, dry_run: args.dry_run?,
                                   verbose: args.verbose?)
          end
        end
      end

      private

      sig { params(keg: Keg).void }
      def puts_keg_only_path_message(keg)
        bin = keg/"bin"
        sbin = keg/"sbin"
        return if !bin.directory? && !sbin.directory?

        opt = HOMEBREW_PREFIX/"opt/#{keg.name}"
        puts "\nIf you need to have this software first in your PATH instead consider running:"
        puts "  #{Utils::Shell.prepend_path_in_profile(opt/"bin")}"  if bin.directory?
        puts "  #{Utils::Shell.prepend_path_in_profile(opt/"sbin")}" if sbin.directory?
      end
    end
  end
end
