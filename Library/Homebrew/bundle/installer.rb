# typed: strict
# frozen_string_literal: true

require "bundle/dsl"
require "bundle/formula_installer"
require "bundle/cask_installer"
require "bundle/mac_app_store_installer"
require "bundle/vscode_extension_installer"
require "bundle/go_installer"
require "bundle/cargo_installer"
require "bundle/flatpak_installer"
require "bundle/tap_installer"
require "bundle/skipper"

module Homebrew
  module Bundle
    module Installer
      sig {
        params(
          entries:    T::Array[Dsl::Entry],
          global:     T::Boolean,
          file:       T.nilable(String),
          no_lock:    T::Boolean,
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          quiet:      T::Boolean,
        ).returns(T::Boolean)
      }
      def self.install!(entries, global: false, file: nil, no_lock: false, no_upgrade: false, verbose: false,
                        force: false, quiet: false)
        success = 0
        failure = 0

        installable_entries = entries.filter_map do |entry|
          next if Homebrew::Bundle::Skipper.skip? entry

          name = entry.name
          args = [name]
          options = {}
          verb = "Installing"
          type = entry.type
          cls = case type
          when :brew
            options = entry.options
            verb = "Upgrading" if Homebrew::Bundle::FormulaInstaller.formula_upgradable?(name)
            Homebrew::Bundle::FormulaInstaller
          when :cask
            options = entry.options
            verb = "Upgrading" if Homebrew::Bundle::CaskInstaller.cask_upgradable?(name)
            Homebrew::Bundle::CaskInstaller
          when :mas
            args << entry.options[:id]
            Homebrew::Bundle::MacAppStoreInstaller
          when :vscode
            Homebrew::Bundle::VscodeExtensionInstaller
          when :go
            Homebrew::Bundle::GoInstaller
          when :cargo
            Homebrew::Bundle::CargoInstaller
          when :flatpak
            options = entry.options
            Homebrew::Bundle::FlatpakInstaller
          when :tap
            verb = "Tapping"
            options = entry.options
            Homebrew::Bundle::TapInstaller
          end
          next if cls.nil?

          { name:, args:, options:, verb:, type:, cls: }
        end

        if (fetchable_names = fetchable_formulae_and_casks(installable_entries, no_upgrade:).presence)
          fetchable_names_joined = fetchable_names.join(", ")
          Formatter.success("Fetching #{fetchable_names_joined}") unless quiet
          unless Bundle.brew("fetch", *fetchable_names, verbose:)
            $stderr.puts Formatter.error "`brew bundle` failed! Failed to fetch #{fetchable_names_joined}"
            return false
          end
        end

        installable_entries.each do |entry|
          name = entry.fetch(:name)
          args = entry.fetch(:args)
          options = entry.fetch(:options)
          verb = entry.fetch(:verb)
          cls = entry.fetch(:cls)

          preinstall = if cls.preinstall!(*args, **options, no_upgrade:, verbose:)
            puts Formatter.success("#{verb} #{name}")
            true
          else
            puts "Using #{name}" unless quiet
            false
          end

          if cls.install!(*args, **options,
                         preinstall:, no_upgrade:, verbose:, force:)
            success += 1
          else
            $stderr.puts Formatter.error("#{verb} #{name} has failed!")
            failure += 1
          end
        end

        unless failure.zero?
          require "utils"
          dependency = Utils.pluralize("dependency", failure)
          $stderr.puts Formatter.error "`brew bundle` failed! #{failure} Brewfile #{dependency} failed to install"
          return false
        end

        unless quiet
          require "utils"
          dependency = Utils.pluralize("dependency", success)
          puts Formatter.success "`brew bundle` complete! #{success} Brewfile #{dependency} now installed."
        end

        true
      end

      sig {
        params(
          entries:    T::Array[{ name:    String,
                                 args:    T::Array[T.anything],
                                 options: T::Hash[Symbol, T.untyped],
                                 verb:    String,
                                 type:    Symbol,
                                 cls:     T::Module[T.anything] }],
          no_upgrade: T::Boolean,
        ).returns(T::Array[String])
      }
      def self.fetchable_formulae_and_casks(entries, no_upgrade:)
        entries.filter_map do |entry|
          name = entry.fetch(:name)
          options = entry.fetch(:options)

          case entry.fetch(:type)
          when :brew
            next unless tap_installed?(name)
            next if Homebrew::Bundle::FormulaInstaller.formula_installed_and_up_to_date?(name, no_upgrade:)

            name
          when :cask
            full_name = options.fetch(:full_name, name)
            next unless tap_installed?(full_name)
            next unless Homebrew::Bundle::CaskInstaller.installable_or_upgradable?(name, no_upgrade:, **options)

            full_name
          end
        end
      end

      sig { params(package_full_name: String).returns(T::Boolean) }
      def self.tap_installed?(package_full_name)
        user, repository, = package_full_name.split("/", 3)
        return true if user.blank? || repository.blank?

        Homebrew::Bundle::TapInstaller.installed_taps.include?("#{user}/#{repository}")
      end
    end
  end
end
