# typed: strict
# frozen_string_literal: true

require "English"
require "abstract_command"
require "ask"
require "cask/uninstall"
require "uninstall"
require "utils"

module Homebrew
  module Cmd
    class Untap < AbstractCommand
      cmd_args do
        description <<~EOS
          Remove a tapped formula repository.
        EOS
        switch "-f", "--force",
               description: "Uninstall all formulae and casks from this tap with `--force` before untapping."

        named_args :tap, min: 1
      end

      sig { override.void }
      def run
        taps = begin
          args.named.to_installed_taps
        rescue Tap::InvalidNameError => e
          odie e.message
        end

        taps.each do |tap|
          if tap.core_tap? && Homebrew::EnvConfig.no_install_from_api?
            ofail "Untapping #{tap} is not allowed"
            next
          end

          installed_tap_formulae, installed_tap_casks = if Homebrew::EnvConfig.no_install_from_api? ||
                                                           (!tap.core_tap? && !tap.core_cask_tap?)
            [installed_formulae_for(tap:), installed_casks_for(tap:)]
          else
            [{}, []]
          end

          if installed_tap_formulae.present? || installed_tap_casks.present?
            installed_formulae_names = installed_tap_formulae.keys
            installed_cask_names = installed_tap_casks.map(&:full_name)
            installed_package_types = if installed_formulae_names.empty?
              "casks"
            elsif installed_cask_names.empty?
              "formulae"
            else
              "formulae and casks"
            end
            installed_names = (installed_formulae_names + installed_cask_names).join("\n")
            if Homebrew::EnvConfig.developer? && !args.force?
              opoo <<~EOS
                Untapping #{tap} even though it contains the following installed #{installed_package_types}:
                #{installed_names}
              EOS
            else
              unless args.force?
                ohai "Would untap #{tap} after uninstalling the following #{installed_package_types}:"
                puts installed_names
                confirmed = begin
                  Homebrew::Ask.confirm?(action: "changes")
                rescue SystemExit
                  false
                end
                unless confirmed
                  ofail <<~EOS
                    Refusing to untap #{tap} because it contains the following installed #{installed_package_types}:
                    #{installed_names}
                  EOS
                  next
                end
              end

              named_args = installed_formulae_names + installed_cask_names
              kegs_by_rack = installed_tap_formulae.values.flatten(1).group_by(&:rack)

              Cask::Uninstall.check_dependent_casks(*installed_tap_casks, named_args:)
              next if Homebrew.failed?

              Uninstall.uninstall_kegs(kegs_by_rack, casks: installed_tap_casks, force: args.force?, named_args:)
              next if Homebrew.failed?

              begin
                Cask::Uninstall.uninstall_casks(*installed_tap_casks, force: args.force?)
              rescue
                ofail $ERROR_INFO
                next
              end

              if installed_formulae_for(tap:).present? || installed_casks_for(tap:).present?
                ofail "Failed to fully uninstall #{installed_package_types} from #{tap}"
                next
              end
            end
          end

          tap.uninstall manual: true
        end
      end

      # Installed kegs for formulae currently available in a tap, keyed by formula full name.
      sig { params(tap: Tap).returns(T::Hash[String, T::Array[Keg]]) }
      def installed_formulae_for(tap:)
        tap.formula_names.filter_map do |formula_name|
          name = Utils.name_from_full_name(formula_name)
          possible_names = [name, *tap.formula_reverse_renames.fetch(name, [])]
          next unless possible_names.any? { |possible_name| installed_formulae_names.include?(possible_name) }

          kegs = begin
            Formulary.factory(formula_name).installed_kegs
          rescue Homebrew::UntrustedTapError
            Utils::Path.formula_installed_prefixes(possible_names).map { |path| Keg.new(path) }
          rescue FormulaUnavailableError, FormulaSpecificationError
            # Don't blow up because of a single unavailable or invalid formula.
            next
          end

          kegs.select! { |keg| keg.tab.tap == tap }
          [formula_name, kegs] if kegs.present?
        end.to_h
      end

      # All installed casks currently available in a tap by cask full name.
      sig { params(tap: Tap).returns(T::Array[Cask::Cask]) }
      def installed_casks_for(tap:)
        require "cask/cask_loader"
        tap.cask_tokens.filter_map do |cask_token|
          next unless installed_cask_tokens.include?(Utils.name_from_full_name(cask_token))

          cask = begin
            Cask::CaskLoader.load(cask_token)
          rescue Cask::CaskUnavailableError, MethodDeprecatedError
            # Don't blow up because of a single unavailable cask or a deprecated method.
            next
          end

          cask if cask.installed? && cask.tab.tap == tap
        end
      end

      private

      sig { returns(T::Set[String]) }
      def installed_formulae_names
        @installed_formulae_names ||= T.let(Formula.installed_formula_names.to_set.freeze, T.nilable(T::Set[String]))
      end

      sig { returns(T::Set[String]) }
      def installed_cask_tokens
        @installed_cask_tokens ||= T.let(Cask::Caskroom.tokens.to_set.freeze, T.nilable(T::Set[String]))
      end
    end
  end
end
