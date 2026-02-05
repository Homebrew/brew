# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module GoInstaller
      sig { void }
      def self.reset!
        @installed_packages = nil
      end

      sig { params(name: String, verbose: T::Boolean, _options: T.anything).returns(T::Boolean) }
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

      sig {
        params(
          name:       String,
          preinstall: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          _options:   T.anything,
        ).returns(T::Boolean)
      }
      def self.install!(name, preinstall: true, verbose: false, force: false, **_options)
        return true unless preinstall

        puts "Installing #{name} Go package. It is not currently installed." if verbose

        go = Bundle.which_go
        return false unless Bundle.system go.to_s, "install", "#{name}@latest", verbose: verbose

        installed_packages << name
        true
      end

      sig { params(package: String).returns(T::Boolean) }
      def self.package_installed?(package)
        installed_packages.include? package
      end

      sig { returns(T::Array[String]) }
      def self.installed_packages
        require "bundle/go_dumper"
        @installed_packages ||= T.let(Homebrew::Bundle::GoDumper.packages, T.nilable(T::Array[String]))
      end
    end
  end
end
