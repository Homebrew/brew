# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    class FormulaInstaller
      def self.reset!
        @installed_formulae = nil
        @outdated_formulae = nil
        @pinned_formulae = nil
      end

      def self.preinstall!(name, no_upgrade: false, verbose: false, **options)
        new(name, options).preinstall!(no_upgrade:, verbose:)
      end

      def self.install!(name, preinstall: true, no_upgrade: false, verbose: false, force: false, **options)
        new(name, options).install!(preinstall:, no_upgrade:, verbose:, force:)
      end

      def initialize(name, options = {})
        @full_name = name
        @name = name.split("/").last
        @args = options.fetch(:args, []).map { |arg| "--#{arg}" }
        @conflicts_with_arg = options.fetch(:conflicts_with, [])
        @restart_service = options[:restart_service]
        @start_service = options.fetch(:start_service, @restart_service)
        @link = options.fetch(:link, nil)
        @postinstall = options.fetch(:postinstall, nil)
        @version_file = options.fetch(:version_file, nil)
        @changed = nil
      end

      def preinstall!(no_upgrade: false, verbose: false)
        if installed? && (self.class.no_upgrade_with_args?(no_upgrade, @name) || !upgradable?)
          puts "Skipping install of #{@name} formula. It is already installed." if verbose
          @changed = nil
          return false
        end

        true
      end

      def install!(preinstall: true, no_upgrade: false, verbose: false, force: false)
        install_result = if preinstall
          install_change_state!(no_upgrade:, verbose:, force:)
        else
          true
        end
        result = install_result

        if installed?
          service_result = service_change_state!(verbose:)
          result &&= service_result

          link_result = link_change_state!(verbose:)
          result &&= link_result

          postinstall_result = postinstall_change_state!(verbose:)
          result &&= postinstall_result

          if result && @version_file.present?
            # Use the version from the environment if it hasn't changed.
            # Strip the revision number because it's not part of the non-Homebrew version.
            version = if !changed? && (env_version = Bundle.formula_versions_from_env(@name))
              PkgVersion.parse(env_version).version
            else
              Formula[@full_name].version
            end.to_s
            File.write(@version_file, "#{version}\n")

            puts "Wrote #{@name} version #{version} to #{@version_file}" if verbose
          end
        end

        result
      end

      def install_change_state!(no_upgrade:, verbose:, force:)
        return false unless resolve_conflicts!(verbose:)

        if installed?
          upgrade_formula!(verbose:, force:)
        else
          install_formula!(verbose:, force:)
        end
      end

      def start_service?
        @start_service.present?
      end

      def start_service_needed?
        require "bundle/brew_services"
        start_service? && !BrewServices.started?(@full_name)
      end

      def restart_service?
        @restart_service.present?
      end

      def restart_service_needed?
        return false unless restart_service?

        # Restart if `restart_service: :always`, or if the formula was installed or upgraded
        @restart_service.to_s == "always" || changed?
      end

      def changed?
        @changed.present?
      end

      def service_change_state!(verbose:)
        require "bundle/brew_services"

        file = Bundle::BrewServices.versioned_service_file(@name)

        if restart_service_needed?
          puts "Restarting #{@name} service." if verbose
          BrewServices.restart(@full_name, file:, verbose:)
        elsif start_service_needed?
          puts "Starting #{@name} service." if verbose
          BrewServices.start(@full_name, file:, verbose:)
        else
          true
        end
      end

      def link_change_state!(verbose: false)
        link_args = []
        link_args << "--force" if unlinked_and_keg_only?

        cmd = case @link
        when :overwrite
          link_args << "--overwrite"
          "link" unless linked?
        when true
          "link" unless linked?
        when false
          "unlink" if linked?
        when nil
          if keg_only?
            "unlink" if linked?
          else
            "link" unless linked?
          end
        end

        if cmd.present?
          verb = "#{cmd}ing".capitalize
          with_args = " with #{link_args.join(" ")}" if link_args.present?
          puts "#{verb} #{@name} formula#{with_args}." if verbose
          return Bundle.brew(cmd, *link_args, @name, verbose:)
        end

        true
      end

      def postinstall_change_state!(verbose:)
        return true if @postinstall.blank?
        return true unless changed?

        puts "Running postinstall for #{@name}: #{@postinstall}" if verbose
        Kernel.system(@postinstall)
      end

      def self.formula_installed_and_up_to_date?(formula, no_upgrade: false)
        return false unless formula_installed?(formula)
        return true if no_upgrade_with_args?(no_upgrade, formula)

        !formula_upgradable?(formula)
      end

      def self.no_upgrade_with_args?(no_upgrade, formula_name)
        no_upgrade && Bundle.upgrade_formulae.exclude?(formula_name)
      end

      def self.formula_in_array?(formula, array)
        return true if array.include?(formula)
        return true if array.include?(formula.split("/").last)

        require "bundle/formula_dumper"
        old_names = Homebrew::Bundle::FormulaDumper.formula_oldnames
        old_name = old_names[formula]
        old_name ||= old_names[formula.split("/").last]
        return true if old_name && array.include?(old_name)

        resolved_full_name = Homebrew::Bundle::FormulaDumper.formula_aliases[formula]
        return false unless resolved_full_name
        return true if array.include?(resolved_full_name)
        return true if array.include?(resolved_full_name.split("/").last)

        false
      end

      def self.formula_installed?(formula)
        formula_in_array?(formula, installed_formulae)
      end

      def self.formula_upgradable?(formula)
        # Check local cache first and then authoritative Homebrew source.
        formula_in_array?(formula, upgradable_formulae) && Formula[formula].outdated?
      end

      def self.installed_formulae
        @installed_formulae ||= formulae.map { |f| f[:name] }
      end

      def self.upgradable_formulae
        outdated_formulae - pinned_formulae
      end

      def self.outdated_formulae
        @outdated_formulae ||= formulae.filter_map { |f| f[:name] if f[:outdated?] }
      end

      def self.pinned_formulae
        @pinned_formulae ||= formulae.filter_map { |f| f[:name] if f[:pinned?] }
      end

      def self.formulae
        require "bundle/formula_dumper"
        Homebrew::Bundle::FormulaDumper.formulae
      end

      private

      def installed?
        FormulaInstaller.formula_installed?(@name)
      end

      def linked?
        Formula[@full_name].linked?
      end

      def keg_only?
        Formula[@full_name].keg_only?
      end

      def unlinked_and_keg_only?
        !linked? && keg_only?
      end

      def upgradable?
        FormulaInstaller.formula_upgradable?(@name)
      end

      def conflicts_with
        @conflicts_with ||= begin
          conflicts_with = Set.new
          conflicts_with += @conflicts_with_arg

          require "bundle/formula_dumper"
          if (formula = Homebrew::Bundle::FormulaDumper.formulae_by_full_name(@full_name)) &&
             (formula_conflicts_with = formula[:conflicts_with])
            conflicts_with += formula_conflicts_with
          end

          conflicts_with.to_a
        end
      end

      def resolve_conflicts!(verbose:)
        conflicts_with.each do |conflict|
          next unless FormulaInstaller.formula_installed?(conflict)

          if verbose
            puts <<~EOS
              Unlinking #{conflict} formula.
              It is currently installed and conflicts with #{@name}.
            EOS
          end
          return false unless Bundle.brew("unlink", conflict, verbose:)

          next unless restart_service?

          require "bundle/brew_services"
          puts "Stopping #{conflict} service (if it is running)." if verbose
          BrewServices.stop(conflict, verbose:)
        end

        true
      end

      def install_formula!(verbose:, force:)
        install_args = @args.dup
        install_args << "--force" << "--overwrite" if force
        install_args << "--skip-link" if @link == false
        with_args = " with #{install_args.join(" ")}" if install_args.present?
        puts "Installing #{@name} formula#{with_args}. It is not currently installed." if verbose
        unless Bundle.brew("install", "--formula", @full_name, *install_args, verbose:)
          @changed = nil
          return false
        end

        FormulaInstaller.installed_formulae << @name
        @changed = true
        true
      end

      def upgrade_formula!(verbose:, force:)
        upgrade_args = []
        upgrade_args << "--force" if force
        with_args = " with #{upgrade_args.join(" ")}" if upgrade_args.present?
        puts "Upgrading #{@name} formula#{with_args}. It is installed but not up-to-date." if verbose
        unless Bundle.brew("upgrade", "--formula", @name, *upgrade_args, verbose:)
          @changed = nil
          return false
        end

        @changed = true
        true
      end
    end
  end
end
