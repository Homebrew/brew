# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    EntryOptionScalar = T.type_alias { T.nilable(T.any(String, Integer, Symbol, TrueClass, FalseClass)) }
    NestedEntryOptionValue = T.type_alias { T.any(EntryOptionScalar, T::Array[String]) }
    NestedEntryOptions = T.type_alias { T::Hash[Symbol, NestedEntryOptionValue] }
    EntryOption = T.type_alias { T.any(EntryOptionScalar, T::Array[String], NestedEntryOptions) }
    EntryOptions = T.type_alias { T::Hash[Symbol, EntryOption] }
    EntryInputOptions = T.type_alias { T::Hash[Symbol, Object] }

    class PackageType
      extend T::Helpers

      abstract!

      sig { params(subclass: T.class_of(Homebrew::Bundle::PackageType)).void }
      def self.inherited(subclass)
        super
        return if subclass.name == "Homebrew::Bundle::Extension"

        Homebrew::Bundle.register_package_type(subclass)
      end

      sig { returns(Symbol) }
      def self.type
        T.cast(const_get(:PACKAGE_TYPE), Symbol)
      end

      sig { returns(T::Boolean) }
      def self.dump_supported?
        true
      end

      sig { returns(T::Boolean) }
      def self.install_supported?
        true
      end

      sig { overridable.params(_name: String, _options: Homebrew::Bundle::EntryOptions).returns(String) }
      def self.install_verb(_name = "", _options = {})
        "Installing"
      end

      sig {
        params(
          name:       String,
          options:    Homebrew::Bundle::EntryOptions,
          no_upgrade: T::Boolean,
        ).returns(T.nilable(String))
      }
      def self.fetchable_name(name, options = {}, no_upgrade: false)
        _ = name
        _ = options
        _ = no_upgrade

        nil
      end

      sig { abstract.void }
      def self.reset!; end

      sig {
        abstract.params(
          name:       String,
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          options:    Homebrew::Bundle::EntryOption,
        ).returns(T::Boolean)
      }
      def self.preinstall!(name, no_upgrade: false, verbose: false, **options); end

      sig {
        abstract.params(
          name:       String,
          preinstall: T::Boolean,
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          options:    Homebrew::Bundle::EntryOption,
        ).returns(T::Boolean)
      }
      def self.install!(name, preinstall: true, no_upgrade: false, verbose: false, force: false, **options); end

      sig {
        params(
          entries:             T::Array[Object],
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[Object])
      }
      def self.check(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        new.find_actionable(entries, exit_on_first_error:, no_upgrade:, verbose:)
      end

      sig { abstract.returns(String) }
      def self.dump; end

      sig { params(describe: T::Boolean, no_restart: T::Boolean).returns(String) }
      def self.dump_output(describe: false, no_restart: false)
        _ = describe
        _ = no_restart

        dump
      end

      sig { params(packages: T::Array[Object], no_upgrade: T::Boolean).returns(T::Array[Object]) }
      def exit_early_check(packages, no_upgrade:)
        work_to_be_done = packages.find do |pkg|
          !installed_and_up_to_date?(pkg, no_upgrade:)
        end

        Array(work_to_be_done)
      end

      sig { overridable.params(name: Object, no_upgrade: T::Boolean).returns(String) }
      def failure_reason(name, no_upgrade:)
        reason = if no_upgrade && Bundle.upgrade_formulae.exclude?(name)
          "needs to be installed."
        else
          "needs to be installed or updated."
        end
        "#{self.class.const_get(:PACKAGE_TYPE_NAME)} #{name} #{reason}"
      end

      sig { params(packages: T::Array[Object], no_upgrade: T::Boolean).returns(T::Array[String]) }
      def full_check(packages, no_upgrade:)
        packages.reject { |pkg| installed_and_up_to_date?(pkg, no_upgrade:) }
                .map { |pkg| failure_reason(pkg, no_upgrade:) }
      end

      sig { params(all_entries: T::Array[Object]).returns(T::Array[Object]) }
      def checkable_entries(all_entries)
        require "bundle/skipper"
        all_entries.filter_map do |entry|
          entry = T.cast(entry, Dsl::Entry)
          next if entry.type != self.class.const_get(:PACKAGE_TYPE)
          next if Bundle::Skipper.skip?(entry)

          entry
        end
      end

      sig { params(entries: T::Array[Object]).returns(T::Array[Object]) }
      def format_checkable(entries)
        checkable_entries(entries).map do |entry|
          entry = T.cast(entry, Dsl::Entry)
          entry.name
        end
      end

      sig { params(_pkg: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(_pkg, no_upgrade: false)
        raise NotImplementedError
      end

      sig {
        params(
          entries:             T::Array[Object],
          exit_on_first_error: T::Boolean,
          no_upgrade:          T::Boolean,
          verbose:             T::Boolean,
        ).returns(T::Array[Object])
      }
      def find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        requested = format_checkable(entries)

        if exit_on_first_error
          exit_early_check(requested, no_upgrade:)
        else
          full_check(requested, no_upgrade:)
        end
      end
    end

    class << self
      sig { params(package_type: T.class_of(PackageType)).void }
      def register_package_type(package_type)
        @package_types ||= T.let([], T.nilable(T::Array[T.class_of(PackageType)]))
        @package_types.reject! { |registered| registered.name == package_type.name }
        @package_types << package_type
      end

      sig { returns(T::Array[T.class_of(PackageType)]) }
      def package_types
        @package_types ||= T.let([], T.nilable(T::Array[T.class_of(PackageType)]))
        @package_types
      end

      sig { params(type: T.any(Symbol, String)).returns(T.nilable(T.class_of(PackageType))) }
      def package_type(type)
        requested_type = type.to_sym
        package_types.find { |registered| registered.type == requested_type }
      end

      sig { returns(T::Array[T.class_of(PackageType)]) }
      def dump_package_types
        core_package_types = [:tap, :brew, :cask].filter_map { |type| package_type(type) }
        (core_package_types + (package_types - core_package_types)).uniq
      end
    end
  end
end
