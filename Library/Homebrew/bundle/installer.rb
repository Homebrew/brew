# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "bundle/dsl"
require "bundle/brew_installer"
require "bundle/cask_installer"
require "bundle/mac_app_store_installer"
require "bundle/whalebrew_installer"
require "bundle/vscode_extension_installer"
require "bundle/tap_installer"
require "bundle/skipper"

module Homebrew
  module Bundle
    module Installer
      def self.install(entries, global: false, file: nil, no_lock: false, no_upgrade: false, verbose: false,
                       force: false, quiet: false)
        success = 0
        failure = 0

        entries.each do |entry|
          name = entry.name
          args = [name]
          options = {}
          verb = "Installing"
          type = entry.type
          cls = case type
          when :brew
            options = entry.options
            verb = "Upgrading" if Homebrew::Bundle::BrewInstaller.formula_upgradable?(name)
            Homebrew::Bundle::BrewInstaller
          when :cask
            options = entry.options
            verb = "Upgrading" if Homebrew::Bundle::CaskInstaller.cask_upgradable?(name)
            Homebrew::Bundle::CaskInstaller
          when :mas
            args << entry.options[:id]
            Homebrew::Bundle::MacAppStoreInstaller
          when :whalebrew
            Homebrew::Bundle::WhalebrewInstaller
          when :vscode
            Homebrew::Bundle::VscodeExtensionInstaller
          when :tap
            verb = "Tapping"
            options = entry.options
            Homebrew::Bundle::TapInstaller
          end

          next if cls.nil?
          next if Homebrew::Bundle::Skipper.skip? entry

          preinstall = if cls.preinstall(*args, **options, no_upgrade:, verbose:)
            puts Formatter.success("#{verb} #{name}")
            true
          else
            puts "Using #{name}" unless quiet
            false
          end

          if cls.install(*args, **options,
                         preinstall:, no_upgrade:, verbose:, force:)
            success += 1
          else
            $stderr.puts Formatter.error("#{verb} #{name} has failed!")
            failure += 1
          end
        end

        unless failure.zero?
          dependency = Homebrew::Bundle::Dsl.pluralize_dependency(failure)
          $stderr.puts Formatter.error "`brew bundle` failed! #{failure} Brewfile #{dependency} failed to install"
          return false
        end

        unless quiet
          dependency = Homebrew::Bundle::Dsl.pluralize_dependency(success)
          puts Formatter.success "`brew bundle` complete! #{success} Brewfile #{dependency} now installed."
        end

        true
      end
    end
  end
end
