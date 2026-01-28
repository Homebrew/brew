# typed: true
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Checker
      class Base
        # Implement these in any subclass
        # PACKAGE_TYPE = :pkg
        # PACKAGE_TYPE_NAME = "Package"

        def exit_early_check(packages, no_upgrade:)
          work_to_be_done = packages.find do |pkg|
            !installed_and_up_to_date?(pkg, no_upgrade:)
          end

          Array(work_to_be_done)
        end

        def failure_reason(name, no_upgrade:)
          reason = if no_upgrade && Bundle.upgrade_formulae.exclude?(name)
            "needs to be installed."
          else
            "needs to be installed or updated."
          end
          "#{self.class.const_get(:PACKAGE_TYPE_NAME)} #{name} #{reason}"
        end

        def full_check(packages, no_upgrade:)
          packages.reject { |pkg| installed_and_up_to_date?(pkg, no_upgrade:) }
                  .map { |pkg| failure_reason(pkg, no_upgrade:) }
        end

        def checkable_entries(all_entries)
          require "bundle/skipper"
          all_entries.select { |e| e.type == self.class.const_get(:PACKAGE_TYPE) }
                     .reject(&Bundle::Skipper.method(:skip?))
        end

        def format_checkable(entries)
          checkable_entries(entries).map(&:name)
        end

        def installed_and_up_to_date?(_pkg, no_upgrade: false)
          raise NotImplementedError
        end

        def find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
          requested = format_checkable entries

          if exit_on_first_error
            exit_early_check(requested, no_upgrade:)
          else
            full_check(requested, no_upgrade:)
          end
        end
      end

      CheckResult = Struct.new :work_to_be_done, :errors

      CHECKS = {
        taps_to_tap:               "Taps",
        casks_to_install:          "Casks",
        extensions_to_install:     "VSCode Extensions",
        apps_to_install:           "Apps",
        formulae_to_install:       "Formulae",
        formulae_to_start:         "Services",
        go_packages_to_install:    "Go Packages",
        cargo_packages_to_install: "Cargo Packages",
        flatpaks_to_install:       "Flatpaks",
      }.freeze

      def self.check(global: false, file: nil, exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/brewfile"
        @dsl ||= Brewfile.read(global:, file:)

        check_method_names = CHECKS.keys

        errors = []
        enumerator = exit_on_first_error ? :find : :map

        work_to_be_done = check_method_names.public_send(enumerator) do |check_method|
          check_errors =
            send(check_method, exit_on_first_error:, no_upgrade:, verbose:)
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
        require "bundle/mac_app_store_checker"
        Homebrew::Bundle::Checker::MacAppStoreChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.extensions_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/vscode_extension_checker"
        Homebrew::Bundle::Checker::VscodeExtensionChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.formulae_to_start(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/brew_service_checker"
        Homebrew::Bundle::Checker::BrewServiceChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.go_packages_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/go_checker"
        Homebrew::Bundle::Checker::GoChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.cargo_packages_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/cargo_checker"
        Homebrew::Bundle::Checker::CargoChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.flatpaks_to_install(exit_on_first_error: false, no_upgrade: false, verbose: false)
        require "bundle/flatpak_checker"
        Homebrew::Bundle::Checker::FlatpakChecker.new.find_actionable(
          @dsl.entries,
          exit_on_first_error:, no_upgrade:, verbose:,
        )
      end

      def self.reset!
        require "bundle/cask_dumper"
        require "bundle/formula_dumper"
        require "bundle/mac_app_store_dumper"
        require "bundle/tap_dumper"
        require "bundle/brew_services"

        @dsl = nil
        Homebrew::Bundle::CaskDumper.reset!
        Homebrew::Bundle::FormulaDumper.reset!
        Homebrew::Bundle::MacAppStoreDumper.reset!
        Homebrew::Bundle::TapDumper.reset!
        Homebrew::Bundle::BrewServices.reset!
      end
    end
  end
end
