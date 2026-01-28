# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module CaskInstaller
      extend ::Utils::Output::Mixin

      def self.reset!
        @installed_casks = nil
        @outdated_casks = nil
      end

      private_class_method def self.upgrading?(no_upgrade, name, options)
        return false if no_upgrade
        return true if cask_upgradable?(name)
        return false unless options[:greedy]

        require "bundle/cask_dumper"
        Homebrew::Bundle::CaskDumper.cask_is_outdated_using_greedy?(name)
      end

      def self.preinstall!(name, no_upgrade: false, verbose: false, **options)
        if cask_installed?(name) && !upgrading?(no_upgrade, name, options)
          puts "Skipping install of #{name} cask. It is already installed." if verbose
          return false
        end

        true
      end

      def self.install!(name, preinstall: true, no_upgrade: false, verbose: false, force: false, **options)
        return true unless preinstall

        full_name = options.fetch(:full_name, name)

        install_result = if cask_installed?(name) && upgrading?(no_upgrade, name, options)
          status = "#{options[:greedy] ? "may not be" : "not"} up-to-date"
          puts "Upgrading #{name} cask. It is installed but #{status}." if verbose
          Bundle.brew("upgrade", "--cask", full_name, verbose:)
        else
          args = options.fetch(:args, []).filter_map do |k, v|
            case v
            when TrueClass
              "--#{k}"
            when FalseClass, NilClass
              nil
            else
              "--#{k}=#{v}"
            end
          end

          args << "--force" if force
          args << "--adopt" unless args.include?("--force")
          args.uniq!

          with_args = " with #{args.join(" ")}" if args.present?
          puts "Installing #{name} cask#{with_args}. It is not currently installed." if verbose

          if Bundle.brew("install", "--cask", full_name, *args, verbose:)
            installed_casks << name
            true
          else
            false
          end
        end
        result = install_result

        if cask_installed?(name)
          postinstall_result = postinstall_change_state!(name:, options:, verbose:)
          result &&= postinstall_result
        end

        result
      end

      def self.installable_or_upgradable?(name, no_upgrade: false, **options)
        !cask_installed?(name) || upgrading?(no_upgrade, name, options)
      end

      private_class_method def self.postinstall_change_state!(name:, options:, verbose:)
        postinstall = options.fetch(:postinstall, nil)
        return true if postinstall.blank?

        puts "Running postinstall for #{@name}: #{postinstall}" if verbose
        Kernel.system(postinstall)
      end

      def self.cask_installed_and_up_to_date?(cask, no_upgrade: false)
        return false unless cask_installed?(cask)
        return true if no_upgrade

        !cask_upgradable?(cask)
      end

      def self.cask_in_array?(cask, array)
        return true if array.include?(cask)

        array.include?(cask.split("/").last)
      end

      def self.cask_installed?(cask)
        return true if cask_in_array?(cask, installed_casks)

        require "bundle/cask_dumper"
        old_names = Homebrew::Bundle::CaskDumper.cask_oldnames
        old_name = old_names[cask]
        old_name ||= old_names[cask.split("/").last]
        return false unless old_name
        return false unless cask_in_array?(old_name, installed_casks)

        opoo "#{cask} was renamed to #{old_name}"

        true
      end

      def self.cask_upgradable?(cask)
        cask_in_array?(cask, outdated_casks)
      end

      def self.installed_casks
        require "bundle/cask_dumper"
        @installed_casks ||= Homebrew::Bundle::CaskDumper.cask_names
      end

      def self.outdated_casks
        require "bundle/cask_dumper"
        @outdated_casks ||= Homebrew::Bundle::CaskDumper.outdated_cask_names
      end
    end
  end
end
