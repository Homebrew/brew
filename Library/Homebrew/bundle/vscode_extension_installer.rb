# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module VscodeExtensionInstaller
      def self.reset!
        @installed_extensions = nil
      end

      def self.preinstall(name, no_upgrade: false, verbose: false)
        if !Bundle.vscode_installed? && Bundle.cask_installed?
          puts "Installing visual-studio-code. It is not currently installed." if verbose
          Bundle.brew("install", "--cask", "visual-studio-code", verbose:)
        end

        if extension_installed?(name)
          puts "Skipping install of #{name} VSCode extension. It is already installed." if verbose
          return false
        end

        raise "Unable to install #{name} VSCode extension. VSCode is not installed." unless Bundle.vscode_installed?

        true
      end

      def self.install(name, preinstall: true, no_upgrade: false, verbose: false, force: false)
        return true unless preinstall
        return true if extension_installed?(name)

        puts "Installing #{name} VSCode extension. It is not currently installed." if verbose

        return false unless Bundle.exchange_uid_if_needed! do
          Bundle.system(T.must(Bundle.which_vscode), "--install-extension", name, verbose:)
        end

        installed_extensions << name

        true
      end

      def self.extension_installed?(name)
        installed_extensions.include? name.downcase
      end

      def self.installed_extensions
        require "bundle/vscode_extension_dumper"
        @installed_extensions ||= Homebrew::Bundle::VscodeExtensionDumper.extensions
      end
    end
  end
end
