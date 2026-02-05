# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module TapInstaller
      sig { params(name: String, verbose: T::Boolean, _options: T.anything).returns(T::Boolean) }
      def self.preinstall!(name, verbose: false, **_options)
        if installed_taps.include? name
          puts "Skipping install of #{name} tap. It is already installed." if verbose
          return false
        end

        true
      end

      sig {
        params(
          name:         String,
          preinstall:   T::Boolean,
          verbose:      T::Boolean,
          force:        T::Boolean,
          clone_target: T.nilable(String),
          _options:     T.anything,
        ).returns(T::Boolean)
      }
      def self.install!(name, preinstall: true, verbose: false, force: false, clone_target: nil, **_options)
        return true unless preinstall

        puts "Installing #{name} tap. It is not currently installed." if verbose
        args = []
        official_tap = name.downcase.start_with? "homebrew/"
        args << "--force" if force || (official_tap && Homebrew::EnvConfig.developer?)

        success = if clone_target
          Bundle.brew("tap", name, clone_target, *args, verbose:)
        else
          Bundle.brew("tap", name, *args, verbose:)
        end

        unless success
          require "bundle/skipper"
          Homebrew::Bundle::Skipper.tap_failed!(name)
          return false
        end

        installed_taps << name
        true
      end

      sig { returns(T::Array[String]) }
      def self.installed_taps
        require "bundle/tap_dumper"
        @installed_taps ||= T.let(Homebrew::Bundle::TapDumper.tap_names, T.nilable(T::Array[String]))
      end
    end
  end
end
