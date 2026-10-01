# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "keg"
require "formula"
require "diagnostic"
require "migrator"
require "cask/cask_loader"
require "cask/exceptions"
require "cask/installer"
require "cask/uninstall"
require "uninstall"
require "trust"

module Homebrew
  module Cmd
    class UninstallCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Uninstall a <formula> or <cask>.
        EOS
        switch "-f", "--force",
               description: "Delete all installed versions of <formula>. Uninstall even if <cask> is not " \
                            "installed, overwrite existing files and ignore errors when removing files."
        switch "--zap",
               description: "Remove all files associated with a <cask>. " \
                            "*May remove files which are shared between applications.*"
        switch "--ignore-dependencies",
               description: "Don't fail uninstall, even if <formula> is a dependency of any installed " \
                            "formulae."
        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."

        conflicts "--formula", "--cask"
        conflicts "--formula", "--zap"

        named_args [:installed_formula, :installed_cask], min: 1
      end

      sig { override.void }
      def run
        method = args.force? ? :kegs : :default_kegs
        results = args.named.to_formulae_and_casks_and_unavailable(method:)

        unavailable_errors = T.let([], T::Array[T.any(FormulaOrCaskUnavailableError, NoSuchKegError)])
        all_kegs = T.let([], T::Array[Keg])
        casks = T.let([], T::Array[Cask::Cask])
        trusted_items_to_remove = T.let([], T::Array[[Symbol, String]])

        results.each do |item|
          case item
          when FormulaOrCaskUnavailableError, NoSuchKegError
            unavailable_errors << item
          when Cask::Cask
            casks << item
            trusted_items_to_remove << [:cask, item.full_name]
          when Keg
            all_kegs << item
            single_keg_tap = item.tab.tap
            trusted_items_to_remove << [:formula, "#{single_keg_tap.name}/#{item.name}"] if single_keg_tap
          when Array
            all_kegs += item
            item.each do |keg|
              array_keg_tap = keg.tab.tap
              trusted_items_to_remove << [:formula, "#{array_keg_tap.name}/#{keg.name}"] if array_keg_tap
            end
          end
        end

        return if all_kegs.blank? && casks.blank? && unavailable_errors.blank?

        kegs_by_rack = all_kegs.group_by(&:rack)

        Uninstall.uninstall_kegs(
          kegs_by_rack,
          casks:,
          force:               args.force?,
          ignore_dependencies: args.ignore_dependencies?,
          named_args:          args.named,
        )

        Cask::Uninstall.check_dependent_casks(*casks, named_args: args.named) unless args.ignore_dependencies?

        return if Homebrew.failed?

        begin
          if args.zap?
            caught_exceptions = []

            casks.each do |cask|
              odebug "Zapping Cask #{cask}"

              raise Cask::CaskNotInstalledError, cask if !cask.installed? && !args.force?

              next unless Cask::Uninstall.unpin_for_removal?(cask, force: args.force?)

              Cask::Installer.new(cask, verbose: args.verbose?, force: args.force?).zap
            rescue => e
              caught_exceptions << e
              next
            end

            if caught_exceptions.count > 1
              raise Cask::MultipleCaskErrors, caught_exceptions
            elsif caught_exceptions.one?
              raise caught_exceptions.fetch(0)
            end
          else
            Cask::Uninstall.uninstall_casks(
              *casks,
              verbose: args.verbose?,
              force:   args.force?,
            )
          end
        rescue => e
          ofail e
        end

        trusted_items_to_remove.uniq.each do |type, name|
          next unless (tap_name = Utils.tap_from_full_name(name))
          next if Homebrew::Trust.trusted?(:tap, tap_name)

          Homebrew::Trust.untrust!(type, name)
        end

        if ENV["HOMEBREW_AUTOREMOVE"].present?
          opoo "`$HOMEBREW_AUTOREMOVE` is now a no-op as it is the default behaviour. " \
               "Set `HOMEBREW_NO_AUTOREMOVE=1` to disable it."
        end
        unless Homebrew::EnvConfig.no_autoremove?
          require "cleanup"
          Cleanup.autoremove
        end

        unavailable_errors.each { |e| ofail e } unless args.force?
      end
    end
  end
end
