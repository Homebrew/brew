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
        all_kegs, casks = args.named.to_kegs_to_casks(
          ignore_unavailable: args.force?,
          all_kegs:           args.force?,
        )

        # If ignore_unavailable is true and the named args
        # are a series of invalid kegs and casks,
        # #to_kegs_to_casks will return empty arrays.
        return if all_kegs.blank? && casks.blank?

        kegs_by_rack = all_kegs.group_by(&:rack)

        Uninstall.uninstall_kegs(
          kegs_by_rack,
          casks:,
          force:               args.force?,
          ignore_dependencies: args.ignore_dependencies?,
          named_args:          args.named,
        )

        if args.zap?
          casks.each do |cask|
            odebug "Zapping Cask #{cask}"

            raise Cask::CaskNotInstalledError, cask if !cask.installed? && !args.force?

            Cask::Installer.new(cask, verbose: args.verbose?, force: args.force?).zap
          end
        else
          Cask::Uninstall.uninstall_casks(
            *casks,
            verbose: args.verbose?,
            force:   args.force?,
          )
        end

        if ENV["HOMEBREW_AUTOREMOVE"].present?
          opoo "HOMEBREW_AUTOREMOVE is now a no-op as it is the default behaviour. " \
               "Set HOMEBREW_NO_AUTOREMOVE=1 to disable it."
        end
        Cleanup.autoremove unless Homebrew::EnvConfig.no_autoremove?
      end
    end
  end
end
