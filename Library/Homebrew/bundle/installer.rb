# typed: strict
# frozen_string_literal: true

require "bundle/dsl"
require "bundle/package_types"
require "bundle/skipper"
require "bundle/trust"
require "trust"
require "utils/output"

module Homebrew
  module Bundle
    module Installer
      extend ::Utils::Output::Mixin

      class InstallableEntry < T::Struct
        const :entry, Dsl::Entry
        const :verb, String
        const :cls, T.class_of(Homebrew::Bundle::PackageType)
        prop :install_name, String

        sig { returns(String) }
        def name = entry.name

        sig { returns(Homebrew::Bundle::EntryOptions) }
        def options = entry.options

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
          quiet:      T::Boolean,
        ).returns(T::Boolean)
      }
      def self.install!(entries, global: false, file: nil, no_lock: false, no_upgrade: false, verbose: false,
                        force: false, quiet: false)
        success = 0
        failure = 0

        installable_entries = T.let([], T::Array[InstallableEntry])
        installable_brewfile_entries = T.let([], T::Array[Dsl::Entry])
        entries.each do |entry|
          next if Homebrew::Bundle::Skipper.skip? entry

          name = entry.name
          options = entry.options
          type = entry.type
          cls = Homebrew::Bundle.installable(type)
          next if cls.nil? || !cls.install_supported?

          installable_brewfile_entries << entry
          installable_entries << InstallableEntry.new(
            entry:, verb: cls.install_verb(name, options), cls:,
            install_name: T.cast(options.fetch(:full_name, name), String)
          )
        end

        # Apply `trusted: true` Brewfile options before anything loads the entries.
        Homebrew::Bundle::Trust.entries(installable_brewfile_entries).each do |type, name|
          Homebrew::Trust.trust!(type, name)
        end

        # Taps first: later entries can live in them, and `ensure_installed!` below
        # needs the ones the Brewfile itself provides to already be present.
        tap_entries, pending_entries = installable_entries.partition { |entry| entry.cls == Tap }
        tap_entries.each do |entry|
          if install_entry!(entry, no_upgrade:, verbose:, force:, quiet:)
            success += 1
          else
            failure += 1
          end
        end
        ::Tap.clear_cache if tap_entries.present?
        installed_taps = ensure_entry_taps_installed!(pending_entries, tap_entries:)
        prepare_attestation_verification!(pending_entries)

        batchable, remaining = pending_entries.partition do |entry|
          homebrew_batchable?(entry, entries: installable_entries, installed_taps:)
        end

        if batchable.present?
          batch_success, batch_failure = batch_install_homebrew!(batchable, no_upgrade:, verbose:, force:, quiet:)
          success += batch_success
          failure += batch_failure
        end

        native_batches, remaining = remaining.partition do |entry|
          entry.cls.batch_installable?(entry.name, entry.options)
        end
        native_batches.group_by(&:cls).each_value do |batch|
          batch_success, batch_failure = batch_install_package_type!(batch, no_upgrade:, verbose:, force:, quiet:)
          success += batch_success
          failure += batch_failure
        end

        remaining.each do |entry|
          if install_entry!(entry, no_upgrade:, verbose:, force:, quiet:)
            success += 1
          else
            failure += 1
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
          !Homebrew::API.formula_name?(entry.name) &&
            Homebrew::API.formula_aliases.exclude?(entry.name) &&
            Homebrew::API.formula_renames.exclude?(entry.name)
        when "Homebrew::Bundle::Cask"
          !Homebrew::API.cask_token?(entry.name) &&
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

      # Installs the taps that entries live in but the Brewfile does not list, returning
      # the names of every tap now installed.
      sig {
        params(
          entries:     T::Array[InstallableEntry],
          tap_entries: T::Array[InstallableEntry],
        ).returns(T::Array[String])
      }
      def self.ensure_entry_taps_installed!(entries, tap_entries:)
        require "tap"

        installed_taps = Tap.installed_taps
        entries.each do |entry|
          tap_with_name = case entry.cls.name
          when "Homebrew::Bundle::Brew" then ::Tap.with_formula_name(entry.full_name)
          when "Homebrew::Bundle::Cask" then ::Tap.with_cask_token(entry.full_name)
          end
          next unless tap_with_name

          tap = tap_with_name.first
          next if installed_taps.include?(tap.name)
          next if tap_entries.any? { |tap_entry| tap_entry.name == tap.name }

          tap.ensure_installed!
          installed_taps << tap.name
        end
        installed_taps
      end
      private_class_method :ensure_entry_taps_installed!

      # Resolve `gh` up front when it is needed to verify attestations, so that the
      # batched install does not have to.
      sig { params(entries: T::Array[InstallableEntry]).void }
      def self.prepare_attestation_verification!(entries)
        return unless Homebrew::EnvConfig.verify_attestations?
        return unless entries.any? { |entry| [Brew, Cask].include?(entry.cls) }
        return if entries.any? { |entry| entry.cls == Brew && entry.name == "gh" }

        require "attestation"

        Homebrew::Attestation.gh_executable
      end
      private_class_method :prepare_attestation_verification!

      # Options that do not change the `brew install` command line, so entries carrying
      # only these can share one invocation.
      BATCHABLE_OPTION_KEYS = [:full_name, :trusted].freeze

      sig {
        params(
          entry:          InstallableEntry,
          entries:        T::Array[InstallableEntry],
          installed_taps: T::Array[String],
        ).returns(T::Boolean)
      }
      def self.homebrew_batchable?(entry, entries:, installed_taps:)
        case entry.cls.name
        when "Homebrew::Bundle::Brew"
          return false if (entry.options.keys - BATCHABLE_OPTION_KEYS).any?
        when "Homebrew::Bundle::Cask"
          return false if (entry.options.keys - [*BATCHABLE_OPTION_KEYS, :args]).any?
          return false if T.cast(entry.options.fetch(:args, {}), Homebrew::Bundle::NestedEntryOptions).present?
        else
          return false
        end
        return false if tap_dependencies(entry, entries:, installed_taps:).present?

        package = if entry.cls == Brew
          require "formula"
          Formula[entry.full_name]
        else
          require "cask/cask_loader"
          ::Cask::CaskLoader.load(entry.full_name)
        end
        return false unless (tap = package.tap)

        entry.install_name = ::Utils.fully_qualified_name(package)
        return true if tap.core_tap? || tap.core_cask_tap?

        if entry.cls == Brew
          tap.cask_tokens.exclude?(entry.install_name)
        else
          tap.formula_names.exclude?(entry.install_name) && tap.aliases.exclude?(entry.install_name)
        end
      rescue
        false
      end
      private_class_method :homebrew_batchable?

      sig {
        params(
          entries:    T::Array[InstallableEntry],
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          quiet:      T::Boolean,
        ).returns([Integer, Integer])
      }
      def self.batch_install_homebrew!(entries, no_upgrade:, verbose:, force:, quiet:)
        actionable = entries.select do |entry|
          if entry.cls.preinstall!(entry.name, **entry.options, no_upgrade:, verbose:)
            puts Formatter.success("#{entry.verb} #{entry.name}")
            true
          else
            puts "Using #{entry.name}" unless quiet
            false
          end
        end

        install_args = []
        install_args << "--adopt" if !force && actionable.any? { |entry| entry.cls == Cask }
        install_args.push("--force", "--overwrite") if force
        batch_succeeded = actionable.empty? || with_env("HOMEBREW_NO_INSTALL_UPGRADE" => nil) do
          Bundle.brew("install", *install_args, *actionable.map(&:install_name), verbose:)
        end

        # The batch changed what is installed, so the memoised views of it are stale.
        require "formula"
        Formula.clear_cache
        Brew.reset!
        Cask.reset!

        success = 0
        failure = 0
        entries.each do |entry|
          # `brew install` exits non-zero if any package failed, so a successful batch
          # means every entry in it succeeded. Only when it failed do we have to ask what
          # ended up installed, since the exit status cannot name the entry that failed.
          entry_succeeded = batch_succeeded || if entry.cls == Brew
                                                 Brew.formula_installed_and_up_to_date?(entry.name, no_upgrade:)
                                               else
                                                 Cask.cask_installed_and_up_to_date?(entry.name, no_upgrade:)
          end
          if entry_succeeded &&
             entry.cls.install!(entry.name, **entry.options, preinstall: false, no_upgrade:, verbose:, force:)
            success += 1
          else
            $stderr.puts Formatter.error("#{entry.verb} #{entry.name} has failed!")
            failure += 1
          end
        end
        [success, failure]
      end
      private_class_method :batch_install_homebrew!

      sig {
        params(
          entries:    T::Array[InstallableEntry],
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          quiet:      T::Boolean,
        ).returns([Integer, Integer])
      }
      def self.batch_install_package_type!(entries, no_upgrade:, verbose:, force:, quiet:)
        cls = entries.fetch(0).cls
        actionable = entries.select do |entry|
          if cls.preinstall!(entry.name, **entry.options, no_upgrade:, verbose:)
            puts Formatter.success("#{entry.verb} #{entry.name}")
            true
          else
            puts "Using #{entry.name}" unless quiet
            false
          end
        end
        return [entries.length, 0] if actionable.empty?

        batch_succeeded = begin
          cls.install_batch!(actionable.map(&:entry), verbose:)
        rescue => e
          opoo "#{cls.check_label} batch installation failed: #{e}" if verbose
          false
        end
        cls.reset!
        return [entries.length, 0] if batch_succeeded

        success = entries.length - actionable.length
        failure = 0
        actionable.each do |entry|
          entry_succeeded = !cls.preinstall!(entry.name, **entry.options, no_upgrade:, verbose: false) ||
                            cls.install!(entry.name, **entry.options, preinstall: true, no_upgrade:, verbose:, force:)
          if entry_succeeded
            success += 1
          else
            $stderr.puts Formatter.error("#{entry.verb} #{entry.name} has failed!")
            failure += 1
          end
        end
        [success, failure]
      end
      private_class_method :batch_install_package_type!

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
