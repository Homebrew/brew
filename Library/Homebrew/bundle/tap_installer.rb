# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module TapInstaller
      def self.preinstall(name, verbose: false, **_options)
        if installed_taps.include? name
          puts "Skipping install of #{name} tap. It is already installed." if verbose
          return false
        end

        true
      end

      def self.install(name, preinstall: true, verbose: false, force: false, **options)
        return true unless preinstall

        puts "Installing #{name} tap. It is not currently installed." if verbose
        args = []
        args << "--force" if force
        args.append("--force-auto-update") if options[:force_auto_update]

        success = if options[:clone_target]
          Bundle.brew("tap", name, options[:clone_target], *args, verbose:)
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

      def self.installed_taps
        require "bundle/tap_dumper"
        @installed_taps ||= Homebrew::Bundle::TapDumper.tap_names
      end
    end
  end
end
