# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module GoInstaller
      def self.reset!
        @installed_packages = nil
      end

      def self.preinstall!(name, verbose: false, **_options)
        unless Bundle.go_installed?
          puts "Installing go. It is not currently installed." if verbose
          Bundle.brew("install", "--formula", "go", verbose:)
          raise "Unable to install #{name} package. Go installation failed." unless Bundle.go_installed?
        end

        if package_installed?(name)
          puts "Skipping install of #{name} Go package. It is already installed." if verbose
          return false
        end

        true
      end

      def self.install!(name, preinstall: true, verbose: false, force: false, **_options)
        return true unless preinstall

        puts "Installing #{name} Go package. It is not currently installed." if verbose

        return false unless Bundle.system "go", "install", "#{name}@latest", verbose: verbose

        installed_packages << name
        true
      end

      def self.package_installed?(package)
        installed_packages.include? package
      end

      def self.installed_packages
        require "bundle/go_dumper"
        @installed_packages ||= Homebrew::Bundle::GoDumper.packages
      end
    end
  end
end
