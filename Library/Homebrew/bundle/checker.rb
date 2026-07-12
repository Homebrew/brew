# typed: strict
# frozen_string_literal: true

require "bundle/dsl"
require "bundle/extensions"
require "bundle/package_types"
require "bundle/brew_services"

module Homebrew
  module Bundle
    module Checker
      class CheckResult < T::Struct
        const :work_to_be_done, T::Boolean
        const :errors, T::Array[String]
      end

      CheckStep = T.type_alias { Symbol }

      CORE_CHECKS = [
        :taps_to_tap,
        :casks_to_install,
        :registered_extensions_to_install,
        :apps_to_install,
        :formulae_to_install,
        :formulae_to_start,
      ].freeze

      sig {
        params(
          global:              T::Boolean,
          file:                T.nilable(String),
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(CheckResult)
      }
      def self.check(global: false, file: nil, exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/brewfile"
        @dsl = T.let(@dsl, T.nilable(Homebrew::Bundle::Dsl))
        @dsl ||= Brewfile.read(global:, file:)

        errors = T.let([], T::Array[String])
        enumerator = exit_on_first_error ? :find : :map

        work_to_be_done = CORE_CHECKS.public_send(enumerator) do |check_step|
          check_errors = public_send(check_step, exit_on_first_error:, no_upgrade:, verbose:)
          any_errors = check_errors.any?
          errors.concat(check_errors) if any_errors
          any_errors
        end

        work_to_be_done = Array(work_to_be_done).flatten.any?

        CheckResult.new(work_to_be_done:, errors:)
      end

      sig {
        params(
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[String])
      }
      def self.apps_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        extension_errors(:apps_to_install, exit_on_first_error:, no_upgrade:, verbose:)
      end

      sig {
        params(
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[String])
      }
      def self.formulae_to_start(exit_on_first_error: false, no_upgrade: false, verbose: false)
        raise ArgumentError, "dsl is unset!" unless @dsl

        Homebrew::Bundle::Brew::Services.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      sig {
        params(
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[String])
      }
      def self.taps_to_tap(exit_on_first_error: false, no_upgrade: false, verbose: false)
        package_type_errors(:tap, exit_on_first_error:, no_upgrade:, verbose:)
      end

      sig {
        params(
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[String])
      }
      def self.casks_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        package_type_errors(:cask, exit_on_first_error:, no_upgrade:, verbose:)
      end

      sig {
        params(
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[String])
      }
      def self.formulae_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        package_type_errors(:brew, exit_on_first_error:, no_upgrade:, verbose:)
      end

      sig {
        params(
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[String])
      }
      def self.registered_extensions_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        extension_errors(:registered_extensions_to_install, exit_on_first_error:, no_upgrade:, verbose:)
      end

      sig {
        params(
          step:                Symbol,
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[String])
      }
      def self.extension_errors(step, exit_on_first_error:, no_upgrade:, verbose:)
        raise ArgumentError, "dsl is unset!" unless @dsl

        matching_extensions = Homebrew::Bundle.extensions.select { |extension| extension.legacy_check_step == step }
        errors = T.let([], T::Array[String])

        matching_extensions.each do |extension|
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

      sig { void }
      def self.reset!
        @dsl = T.let(nil, T.nilable(Homebrew::Bundle::Dsl))
        Homebrew::Bundle.package_types.each(&:reset!)
        Homebrew::Bundle.extensions.each(&:reset!)
      end

      sig {
        params(
          type:                Symbol,
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[String])
      }
      def self.package_type_errors(type, exit_on_first_error:, no_upgrade:, verbose:)
        raise ArgumentError, "dsl is unset!" unless @dsl

        package_type = Homebrew::Bundle.package_type(type)
        return [] if package_type.nil?

        package_type.check(@dsl.entries, exit_on_first_error:, no_upgrade:, verbose:)
      end
    end
  end
end
