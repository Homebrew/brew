# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module FlatpakRemoteInstaller
      def self.reset!
        @installed_remotes = nil
      end

      def self.preinstall!(name, verbose: false, **_options)
        return false if OS.mac?

        unless Bundle.flatpak_installed?
          puts "Installing flatpak. It is not currently installed." if verbose
          Bundle.brew("install", "--formula", "flatpak", verbose:)
          raise "Unable to add #{name} remote. Flatpak installation failed." unless Bundle.flatpak_installed?
        end

        if installed_remotes.include?(name)
          puts "Skipping add of #{name} flatpak remote. It is already added." if verbose
          return false
        end

        true
      end

      def self.install!(name, preinstall: true, verbose: false, force: false, **options)
        return true unless preinstall

        url = options[:url]

        if url.nil?
          puts "Flatpak remote #{name} requires a URL to be specified." if verbose
          return false
        end

        puts "Adding #{name} flatpak remote. It is not currently added." if verbose

        flatpak = Bundle.which_flatpak
        args = ["remote-add", "--if-not-exists", "--system", name, url]

        success = Bundle.system(flatpak.to_s, *args, verbose:)

        unless success
          require "bundle/skipper"
          Homebrew::Bundle::Skipper.flatpak_remote_failed!(name)
          return false
        end

        installed_remotes << name
        true
      end

      def self.installed_remotes
        require "bundle/flatpak_remote_dumper"
        @installed_remotes ||= Homebrew::Bundle::FlatpakRemoteDumper.remote_names
      end
    end
  end
end
