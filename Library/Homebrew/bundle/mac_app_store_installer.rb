# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "os"

module Homebrew
  module Bundle
    module MacAppStoreInstaller
      def self.reset!
        @installed_app_ids = nil
        @outdated_app_ids = nil
      end

      def self.preinstall(name, id, no_upgrade: false, verbose: false)
        unless Bundle.mas_installed?
          puts "Installing mas. It is not currently installed." if verbose
          Bundle.brew("install", "mas", verbose:)
          raise "Unable to install #{name} app. mas installation failed." unless Bundle.mas_installed?
        end

        if app_id_installed?(id) &&
           (no_upgrade || !app_id_upgradable?(id))
          puts "Skipping install of #{name} app. It is already installed." if verbose
          return false
        end

        true
      end

      def self.install(name, id, preinstall: true, no_upgrade: false, verbose: false, force: false)
        return true unless preinstall

        if app_id_installed?(id)
          puts "Upgrading #{name} app. It is installed but not up-to-date." if verbose
          return false unless Bundle.system "mas", "upgrade", id.to_s, verbose: verbose

          return true
        end

        puts "Installing #{name} app. It is not currently installed." if verbose

        return false unless Bundle.system "mas", "install", id.to_s, verbose: verbose

        installed_app_ids << id
        true
      end

      def self.app_id_installed_and_up_to_date?(id, no_upgrade: false)
        return false unless app_id_installed?(id)
        return true if no_upgrade

        !app_id_upgradable?(id)
      end

      def self.app_id_installed?(id)
        installed_app_ids.include? id
      end

      def self.app_id_upgradable?(id)
        outdated_app_ids.include? id
      end

      def self.installed_app_ids
        require "bundle/mac_app_store_dumper"
        @installed_app_ids ||= Homebrew::Bundle::MacAppStoreDumper.app_ids
      end

      def self.outdated_app_ids
        @outdated_app_ids ||= if Bundle.mas_installed?
          `mas outdated 2>/dev/null`.split("\n").map do |app|
            app.split(" ", 2).first.to_i
          end
        else
          []
        end
      end
    end
  end
end
