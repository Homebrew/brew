# typed: true
# frozen_string_literal: true

require "bundle/checker/base"
require "bundle/dsl"
require "bundle/extensions"

module Homebrew
  module Bundle
    module Checker
      CheckResult = Struct.new :work_to_be_done, :errors
      CheckStep = T.type_alias { Symbol }

      CORE_CHECKS = T.let([
        :taps_to_tap,
        :casks_to_install,
        :registered_extensions_to_install,
        :formulae_to_install,
        :formulae_to_start,
      ].freeze, T::Array[CheckStep])

      def self.check(global: false, file: nil, exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/brewfile"
        @dsl ||= Brewfile.read(global:, file:)

        errors = []
        enumerator = exit_on_first_error ? :find : :map

        work_to_be_done = check_steps.public_send(enumerator) do |check_step|
          check_errors = run_check_step(check_step, exit_on_first_error:, no_upgrade:, verbose:)
          any_errors = check_errors.any?
          errors.concat(check_errors) if any_errors
          any_errors
        end

        work_to_be_done = Array(work_to_be_done).flatten.any?

        CheckResult.new work_to_be_done, errors
      end

      def self.casks_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/cask_checker"
        Homebrew::Bundle::Checker::CaskChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.formulae_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/brew_checker"
        Homebrew::Bundle::Checker::BrewChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.taps_to_tap(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/tap_checker"
        Homebrew::Bundle::Checker::TapChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.apps_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        _ = exit_on_first_error
        _ = no_upgrade
        _ = verbose

        # TODO: Remove this legacy no-op once callers and tests stop referencing
        # the old dedicated app check phase.
        []
      end

      def self.extensions_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        _ = exit_on_first_error
        _ = no_upgrade
        _ = verbose

        # TODO: Remove this legacy no-op once callers and tests stop referencing
        # the old dedicated extension check phase.
        []
      end

      def self.formulae_to_start(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/brew_service_checker"
        Homebrew::Bundle::Checker::BrewServiceChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.registered_extensions_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        errors = T.let([], T::Array[Object])

        Homebrew::Bundle.extensions.each do |extension|
          check_errors = extension.check(
            @dsl.entries,
            exit_on_first_error:, no_upgrade:, verbose:,
          )
          next if check_errors.empty?

          return check_errors if exit_on_first_error

          errors.concat(check_errors)
        end

        errors
      end

      def self.reset!
        require "bundle/cask_dumper"
        require "bundle/formula_dumper"
        require "bundle/tap_dumper"
        require "bundle/brew_services"

        @dsl = nil
        Homebrew::Bundle::CaskDumper.reset!
        Homebrew::Bundle::FormulaDumper.reset!
        Homebrew::Bundle::TapDumper.reset!
        Homebrew::Bundle::BrewServices.reset!
        Homebrew::Bundle.extensions.each(&:reset!)
      end

      sig { returns(T::Array[CheckStep]) }
      def self.check_steps
        CORE_CHECKS
      end

      sig {
        params(
          check_step:          CheckStep,
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[Object])
      }
      def self.run_check_step(check_step, exit_on_first_error:, no_upgrade:, verbose:)
        public_send(check_step, exit_on_first_error:, no_upgrade:, verbose:)
      end
    end
  end
end
