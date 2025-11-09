# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module FlatpakInstaller
      def self.reset!
        @installed_packages = nil
      end

      def self.preinstall!(name, verbose: false, remote: "flathub", **_options)
        return false if OS.mac?

        unless Bundle.flatpak_installed?
          puts "Installing flatpak. It is not currently installed." if verbose
          Bundle.brew("install", "--formula", "flatpak", verbose:)
          raise "Unable to install #{name} package. Flatpak installation failed." unless Bundle.flatpak_installed?
        end

        if package_installed?(name, remote:)
          puts "Skipping install of #{name} Flatpak. It is already installed." if verbose
          return false
        end

        true
      end

      def self.install!(name, preinstall: true, verbose: false, force: false, remote: "flathub", **_options)
        return true unless preinstall

        puts "Installing #{name} Flatpak from #{remote}. It is not currently installed." if verbose

        flatpak = Bundle.which_flatpak
        # Install from specified remote (defaults to flathub for backward compatibility)
        return false unless Bundle.system flatpak.to_s, "install", "-y", "--system", remote, name, verbose: verbose

        installed_packages << { name:, remote: }
        true
      end

      def self.package_installed?(package, remote: nil)
        if remote
          # Check if package is installed from the specified remote
          installed_packages.any? { |pkg| pkg[:name] == package && pkg[:remote] == remote }
        else
          # Just check if package is installed from any remote
          installed_packages.any? { |pkg| pkg[:name] == package }
        end
      end

      def self.installed_packages
        require "bundle/flatpak_dumper"
        @installed_packages ||= Homebrew::Bundle::FlatpakDumper.packages_with_remotes
      end
    end
  end
end
