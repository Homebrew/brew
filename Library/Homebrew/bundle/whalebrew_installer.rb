# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module WhalebrewInstaller
      def self.reset!
        @installed_images = nil
      end

      def self.preinstall(name, verbose: false, **_options)
        unless Bundle.whalebrew_installed?
          puts "Installing whalebrew. It is not currently installed." if verbose
          Bundle.brew("install", "--formula", "whalebrew", verbose:)
          raise "Unable to install #{name} app. Whalebrew installation failed." unless Bundle.whalebrew_installed?
        end

        if image_installed?(name)
          puts "Skipping install of #{name} app. It is already installed." if verbose
          return false
        end

        true
      end

      def self.install(name, preinstall: true, verbose: false, force: false, **_options)
        odeprecated "`brew bundle` `whalebrew` support", "using `whalebrew` directly"
        return true unless preinstall

        puts "Installing #{name} image. It is not currently installed." if verbose

        return false unless Bundle.system "whalebrew", "install", name, verbose: verbose

        installed_images << name
        true
      end

      def self.image_installed?(image)
        installed_images.include? image
      end

      def self.installed_images
        require "bundle/whalebrew_dumper"
        @installed_images ||= Homebrew::Bundle::WhalebrewDumper.images
      end
    end
  end
end
