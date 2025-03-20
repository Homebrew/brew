# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module WhalebrewInstaller
      module_function

      def reset!
        @installed_images = nil
      end

      def preinstall(name, verbose: false, **_options)
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

      def install(name, preinstall: true, verbose: false, force: false, **_options)
        # odeprecated "`brew bundle` `whalebrew` support", "using `whalebrew` directly"
        return true unless preinstall

        puts "Installing #{name} image. It is not currently installed." if verbose

        return false unless Bundle.system "whalebrew", "install", name, verbose: verbose

        installed_images << name
        true
      end

      def image_installed?(image)
        installed_images.include? image
      end

      def installed_images
        @installed_images ||= Homebrew::Bundle::WhalebrewDumper.images
      end
    end
  end
end
