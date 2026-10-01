# typed: strict
# frozen_string_literal: true

require "keg"
require "utils/output"

module Homebrew
  module Install
    extend Utils::Output::Mixin

    class << self
      sig {
        params(formula: Formula, head: T::Boolean, fetch_head: T::Boolean,
               only_dependencies: T::Boolean, force: T::Boolean, quiet: T::Boolean,
               skip_link: T::Boolean, overwrite: T::Boolean).returns(T::Boolean)
      }
      def install_formula?(
        formula,
        head: false,
        fetch_head: false,
        only_dependencies: false,
        force: false,
        quiet: false,
        skip_link: false,
        overwrite: false
      )
        # HEAD-only without --HEAD is an error
        if !head && formula.stable.nil?
          odie <<~EOS
            #{formula.full_name} is a HEAD-only formula.
            To install it, run:
              brew install --HEAD #{formula.full_name}
          EOS
        end

        # --HEAD, fail with no head defined
        odie "No head is defined for #{formula.full_name}" if head && formula.head.nil?

        installed_head_version = formula.latest_head_version
        if installed_head_version &&
           !formula.head_version_outdated?(installed_head_version, fetch_head:)
          new_head_installed = true
        end
        prefix_installed = formula.prefix.exist? && !formula.prefix.empty?

        # Check if the installed formula is from a different tap
        if formula.any_version_installed? &&
           (current_tap_name = formula.tap&.name.presence) &&
           (installed_keg_tab = formula.any_installed_keg&.tab.presence) &&
           (installed_tap_name = installed_keg_tab.tap&.name.presence) &&
           installed_tap_name != current_tap_name
          odie <<~EOS
            #{formula.name} was installed from the #{Formatter.identifier(installed_tap_name)} tap
            but you are trying to install it from the #{Formatter.identifier(current_tap_name)} tap.
            Formulae with the same name from different taps cannot be installed at the same time.

            To install this version, you must first uninstall the existing formula:
              brew uninstall #{formula.name}
            Then you can install the desired version:
              brew install #{formula.full_name}
          EOS
        end

        if formula.keg_only? && formula.any_version_installed? && formula.optlinked? && !force
          # keg-only install is only possible when no other version is
          # linked to opt, because installing without any warnings can break
          # dependencies. Therefore before performing other checks we need to be
          # sure the --force switch is passed.
          if formula.outdated?
            if !Homebrew::EnvConfig.no_install_upgrade? && !formula.pinned?
              name = formula.name
              version = formula.linked_version
              puts "#{name} #{version} is already installed but outdated (so it will be upgraded)."
              return true
            end

            unpin_cmd_if_needed = ("brew unpin #{formula.full_name} && " if formula.pinned?)
            optlinked_version = Keg.for(formula.opt_prefix).version
            onoe <<~EOS
              #{formula.full_name} #{optlinked_version} is already installed.
              To upgrade to #{formula.version}, run:
                #{unpin_cmd_if_needed}brew upgrade #{formula.full_name}
            EOS
          elsif only_dependencies
            return true
          elsif !quiet
            opoo_without_github_actions_annotation <<~EOS
              #{formula.full_name} #{formula.pkg_version} is already installed and up-to-date.
              To reinstall #{formula.pkg_version}, run:
                brew reinstall #{formula.name}
            EOS
          end
        elsif (head && new_head_installed) || prefix_installed
          # After we're sure the --force switch was passed for linking to opt
          # keg-only we need to be sure that the version we're attempting to
          # install is not already installed.

          installed_version = if head
            formula.latest_head_version
          else
            formula.pkg_version
          end

          msg = "#{formula.full_name} #{installed_version} is already installed"
          linked_not_equals_installed = formula.linked_version != installed_version
          if formula.linked? && linked_not_equals_installed
            msg = if quiet
              nil
            else
              <<~EOS
                #{msg}.
                The currently linked version is: #{formula.linked_version}
              EOS
            end
          elsif only_dependencies || (!formula.linked? && overwrite)
            msg = nil
            return true
          elsif !formula.linked? || formula.keg_only?
            msg = <<~EOS
              #{msg}, it's just not linked.
              To link this version, run:
                brew link #{formula.full_name}
            EOS
          else
            unless quiet
              opoo_without_github_actions_annotation <<~EOS
                #{msg} and up-to-date.
                To reinstall #{formula.pkg_version}, run:
                  brew reinstall #{formula.name}
              EOS
            end
            msg = nil
          end
          opoo msg if msg
        elsif !formula.any_version_installed? && (old_formula = formula.old_installed_formulae.first)
          msg = "#{old_formula.full_name} #{old_formula.any_installed_version} already installed"
          msg = if !old_formula.linked? && !old_formula.keg_only?
            <<~EOS
              #{msg}, it's just not linked.
              To link this version, run:
                brew link #{old_formula.full_name}
            EOS
          elsif quiet
            nil
          else
            "#{msg}."
          end
          opoo msg if msg
        elsif formula.migration_needed? && !force
          # Check if the formula we try to install is the same as installed
          # but not migrated one. If --force is passed then install anyway.
          opoo <<~EOS
            #{formula.oldnames_to_migrate.first} is already installed, it's just not migrated.
            To migrate this formula, run:
              brew migrate #{formula}
            Or to force-install it, run:
              brew install #{formula} --force
          EOS
        elsif formula.linked?
          message = "#{formula.name} #{formula.linked_version} is already installed"
          if formula.outdated? && !head
            if !Homebrew::EnvConfig.no_install_upgrade? && !formula.pinned?
              puts "#{message} but outdated (so it will be upgraded)."
              return true
            end

            unpin_cmd_if_needed = ("brew unpin #{formula.full_name} && " if formula.pinned?)
            onoe <<~EOS
              #{message}
              To upgrade to #{formula.pkg_version}, run:
                #{unpin_cmd_if_needed}brew upgrade #{formula.full_name}
            EOS
          elsif only_dependencies || skip_link
            return true
          else
            onoe <<~EOS
              #{message}
              To install #{formula.pkg_version}, first run:
                brew unlink #{formula.name}
            EOS
          end
        else
          # If none of the above is true and the formula is linked, then
          # FormulaInstaller will handle this case.
          return true
        end

        # Even if we don't install this formula mark it as no longer just
        # installed as a dependency.
        return false unless formula.opt_prefix.directory?

        keg = Keg.new(Utils::Path.resolved_path(formula.opt_prefix))
        tab = keg.tab
        unless tab.installed_on_request
          tab.installed_on_request = true
          tab.write
        end

        false
      end
    end
  end
end
