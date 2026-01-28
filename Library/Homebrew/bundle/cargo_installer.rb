# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module CargoInstaller
      sig { void }
      def self.reset!
        @installed_packages = nil
      end

      sig { params(name: String, verbose: T::Boolean, _options: T.anything).returns(T::Boolean) }
      def self.preinstall!(name, verbose: false, **_options)
        unless Bundle.cargo_installed?
          puts "Installing rust for cargo. It is not currently installed." if verbose
          Bundle.brew("install", "--formula", "rust", verbose:)
          Bundle.reset!
          raise "Unable to install #{name} package. Rust installation failed." unless Bundle.cargo_installed?
        end

        if package_installed?(name)
          puts "Skipping install of #{name} Cargo package. It is already installed." if verbose
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

        puts "Installing #{name} Cargo package. It is not currently installed." if verbose

        cargo = T.must(Bundle.which_cargo)
        env = { "PATH" => "#{cargo.dirname}:#{ENV.fetch("PATH")}" }
        success = with_env(env) do
          Bundle.system cargo.to_s, "install", "--locked", name, verbose:
        end
        return false unless success

        installed_packages << name
        true
      end

      sig { params(package: String).returns(T::Boolean) }
      def self.package_installed?(package)
        installed_packages.include? package
      end

      sig { returns(T::Array[String]) }
      def self.installed_packages
        require "bundle/cargo_dumper"
        @installed_packages ||= T.let(Homebrew::Bundle::CargoDumper.packages, T.nilable(T::Array[String]))
      end
    end
  end
end
