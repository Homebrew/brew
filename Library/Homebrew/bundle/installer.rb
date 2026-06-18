# typed: strict
# frozen_string_literal: true

require "bundle/dsl"
require "bundle/package_types"
require "bundle/skipper"
require "utils/output"

module Homebrew
  module Bundle
    module Installer
      extend ::Utils::Output::Mixin

      class InstallableEntry < T::Struct
        const :name, String
        const :options, Homebrew::Bundle::EntryOptions
        const :verb, String
        const :cls, T.class_of(Homebrew::Bundle::PackageType)

        sig { returns(String) }
        def full_name
          T.cast(options.fetch(:full_name, name), String)
        end

        sig { returns(T.nilable(String)) }
        def tap_name
          ::Utils.tap_from_full_name(full_name)
        end
      end

      sig { void }
      def self.reset!
        Homebrew::Bundle.reset!
        Homebrew::Bundle::Cask.reset!
        Homebrew::Bundle::Tap.reset!
      end

      sig {
        params(
          entries:    T::Array[Dsl::Entry],
          global:     T::Boolean,
          file:       T.nilable(String),
          no_lock:    T::Boolean,
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          jobs:       Integer,
          quiet:      T::Boolean,
        ).returns(T::Boolean)
      }
      def self.install!(entries, global: false, file: nil, no_lock: false, no_upgrade: false, verbose: false,
                        force: false, jobs: 1, quiet: false)
        success = 0
        failure = 0

        installable_entries = entries.filter_map do |entry|
          next if Homebrew::Bundle::Skipper.skip? entry

          name = entry.name
          options = entry.options
          type = entry.type
          cls = Homebrew::Bundle.installable(type)
          next if cls.nil? || !cls.install_supported?

          InstallableEntry.new(name:, options:, verb: cls.install_verb(name, options), cls:)
        end

        apply_trust!(installable_entries)

        if (fetchable_names = fetchable_formulae_and_casks(installable_entries, no_upgrade:).presence)
          fetchable_names_joined = fetchable_names.join(", ")
          puts Formatter.success("Fetching #{fetchable_names_joined}") unless quiet
          unless Bundle.brew("fetch", *fetchable_names, verbose:)
            $stderr.puts Formatter.error "`brew bundle` failed! Failed to fetch #{fetchable_names_joined}"
            return false
          end
        end

        if jobs > 1 && installable_entries.size > 1
          require "bundle/parallel_installer"

          parallel = ParallelInstaller.new(
            installable_entries, jobs:, no_upgrade:, verbose:, force:, quiet:
          )
          parallel_success, parallel_failure = parallel.run!
          success += parallel_success
          failure += parallel_failure
        else
          installable_entries.each do |entry|
            if install_entry!(entry, no_upgrade:, verbose:, force:, quiet:)
              success += 1
            else
              failure += 1
            end
          end
        end

        unless failure.zero?
          require "utils"
          dependency = Utils.pluralize("dependency", failure)
          $stderr.puts Formatter.error "`brew bundle` failed! #{failure} Brewfile #{dependency} failed to install"
          return false
        end

        unless quiet
          require "utils"
          dependency = Utils.pluralize("dependency", success)
          puts Formatter.success "`brew bundle` complete! #{success} Brewfile #{dependency} now installed."
        end

        true
      end

      # Apply `trusted: true` Brewfile options before anything fetches or
      # loads the entries: the fetch phase and upgrade checks load formulae
      # and casks, which triggers the tap trust check before the per-entry
      # install step could grant trust.
      sig { params(entries: T::Array[InstallableEntry]).void }
      def self.apply_trust!(entries)
        entries.each do |entry|
          next unless entry.options[:trusted]

          require "trust"

          if entry.cls == Tap
            clone_target = entry.options[:clone_target].presence
            reference = if clone_target
              require "tap"
              ::Tap.remote_to_reference(clone_target.to_s) || clone_target.to_s
            else
              entry.name
            end
            Homebrew::Trust.trust!(:tap, reference)
          elsif ::Utils.full_name?(entry.full_name)
            # Only fully-qualified names map to a tap, so unqualified names
            # cannot be meaningfully trusted.
            if entry.cls == Brew
              Homebrew::Trust.trust!(:formula, entry.full_name)
            elsif entry.cls == Cask
              Homebrew::Trust.trust!(:cask, entry.full_name)
            end
          end
        end
      end
      private_class_method :apply_trust!

      sig {
        params(
          entries:    T::Array[InstallableEntry],
          no_upgrade: T::Boolean,
        ).returns(T::Array[String])
      }
      def self.fetchable_formulae_and_casks(entries, no_upgrade:)
        installed_taps = Tap.installed_taps

        entries.filter_map do |entry|
          next if tap_dependencies(entry, entries:, installed_taps:).present?

          entry.cls.fetchable_name(entry.name, entry.options, no_upgrade:)
        end
      end

      sig {
        params(
          entry:          InstallableEntry,
          entries:        T::Array[InstallableEntry],
          installed_taps: T::Array[String],
        ).returns(T::Array[String])
      }
      def self.tap_dependencies(entry, entries:, installed_taps:)
        return [] unless [Brew, Cask].include?(entry.cls)

        if (tap_name = entry.tap_name)
          return installed_taps.exclude?(tap_name) ? [tap_name] : []
        end

        tap_names = entries.filter_map do |tap_entry|
          tap_entry.name if tap_entry.cls == Tap && installed_taps.exclude?(tap_entry.name)
        end
        return [] if tap_names.empty?
        return [] unless unavailable_without_tap?(entry)

        tap_names
      end

      sig { params(entry: InstallableEntry).returns(T::Boolean) }
      def self.unavailable_without_tap?(entry)
        require "api"

        case entry.cls.name
        when "Homebrew::Bundle::Brew"
          Homebrew::API.formula_names.exclude?(entry.name) &&
            Homebrew::API.formula_aliases.exclude?(entry.name) &&
            Homebrew::API.formula_renames.exclude?(entry.name)
        when "Homebrew::Bundle::Cask"
          Homebrew::API.cask_tokens.exclude?(entry.name) &&
            Homebrew::API.cask_renames.exclude?(entry.name)
        else
          false
        end
      rescue => e
        opoo "Treating `#{entry.name}` as dependent on Brewfile taps because Homebrew could not " \
             "check API metadata: #{e}"
        true
      end
      private_class_method :unavailable_without_tap?

      sig {
        params(
          entry:      InstallableEntry,
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          quiet:      T::Boolean,
        ).returns(T::Boolean)
      }
      def self.install_entry!(entry, no_upgrade:, verbose:, force:, quiet:)
        name = entry.name
        options = entry.options
        verb = entry.verb
        cls = entry.cls

        preinstall = if cls.preinstall!(name, **options, no_upgrade:, verbose:)
          puts Formatter.success("#{verb} #{name}")
          true
        else
          puts "Using #{name}" unless quiet
          false
        end

        if cls.install!(name, **options,
                        preinstall:, no_upgrade:, verbose:, force:)
          true
        else
          $stderr.puts Formatter.error("#{verb} #{name} has failed!")
          false
        end
      end
      private_class_method :install_entry!
    end
  end
end
