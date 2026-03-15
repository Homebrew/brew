# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Checker
      class Base
        # Implement these in any subclass
        # PACKAGE_TYPE = :pkg
        # PACKAGE_TYPE_NAME = "Package"
        # TODO: Replace these `T.untyped` checker-base signatures once the
        # remaining non-extension checkers share a typed package model.

        sig { params(packages: T.untyped, no_upgrade: T::Boolean).returns(T::Array[T.untyped]) }
        def exit_early_check(packages, no_upgrade:)
          work_to_be_done = packages.find do |pkg|
            !installed_and_up_to_date?(pkg, no_upgrade:)
          end

          Array(work_to_be_done)
        end

        sig { params(name: T.untyped, no_upgrade: T::Boolean).returns(String) }
        def failure_reason(name, no_upgrade:)
          reason = if no_upgrade && Bundle.upgrade_formulae.exclude?(name)
            "needs to be installed."
          else
            "needs to be installed or updated."
          end
          "#{self.class.const_get(:PACKAGE_TYPE_NAME)} #{name} #{reason}"
        end

        sig { params(packages: T.untyped, no_upgrade: T::Boolean).returns(T::Array[String]) }
        def full_check(packages, no_upgrade:)
          packages.reject { |pkg| installed_and_up_to_date?(pkg, no_upgrade:) }
                  .map { |pkg| failure_reason(pkg, no_upgrade:) }
        end

        sig { params(all_entries: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def checkable_entries(all_entries)
          require "bundle/skipper"
          all_entries.filter_map do |entry|
            entry = T.cast(entry, Dsl::Entry)
            next if entry.type != self.class.const_get(:PACKAGE_TYPE)
            next if Bundle::Skipper.skip?(entry)

            entry
          end
        end

        sig { params(entries: T::Array[T.untyped]).returns(T.untyped) }
        def format_checkable(entries)
          checkable_entries(entries).map do |entry|
            entry = T.cast(entry, Dsl::Entry)
            entry.name
          end
        end

        sig { params(_pkg: T.untyped, no_upgrade: T::Boolean).returns(T::Boolean) }
        def installed_and_up_to_date?(_pkg, no_upgrade: false)
          raise NotImplementedError
        end

        sig {
          params(
            entries:             T::Array[T.untyped],
            exit_on_first_error: T::Boolean,
            no_upgrade:          T::Boolean,
            verbose:             T::Boolean,
          ).returns(T::Array[T.untyped])
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
    end

    ExtensionTypes = T.type_alias { T::Hash[Symbol, T::Boolean] }

    class Extension < Homebrew::Bundle::Checker::Base
      extend T::Helpers

      EntryOptions = T.type_alias { T::Hash[Symbol, Object] }

      abstract!

      sig { params(subclass: T.class_of(Homebrew::Bundle::Extension)).void }
      def self.inherited(subclass)
        super
        Homebrew::Bundle.register_extension(subclass)
      end

      sig { returns(Symbol) }
      def self.type
        T.cast(const_get(:PACKAGE_TYPE), Symbol)
      end

      sig { returns(String) }
      def self.check_label
        T.cast(const_get(:PACKAGE_TYPE_NAME), String)
      end

      sig { returns(String) }
      def self.banner_name
        T.cast(const_get(:BANNER_NAME), String)
      end

      sig { returns(String) }
      def self.switch_description
        if cleanup_supported?
          "`list`, `dump` or `cleanup` #{banner_name}."
        else
          "`list` or `dump` #{banner_name}."
        end
      end

      sig { params(name: String, options: EntryOptions).returns(Dsl::Entry) }
      def self.entry(name, options = {})
        raise "unknown options(#{options.keys.inspect}) for #{type}" if options.present?

        Dsl::Entry.new(type, name)
      end

      sig { returns(String) }
      def self.flag
        type.to_s.tr("_", "-")
      end

      sig { returns(Symbol) }
      def self.predicate_method
        :"#{type}?"
      end

      sig { returns(String) }
      def self.package_manager_name
        flag
      end

      # TODO: Route these through each extension once the go/uv specs stop
      # stubbing `Homebrew::Bundle.which_*` and `*_installed?` directly.
      sig { returns(T::Boolean) }
      def self.package_manager_installed?
        Bundle.public_send(:"#{type}_installed?")
      end

      sig { returns(T.nilable(Pathname)) }
      def self.package_manager_executable
        Bundle.public_send(:"which_#{type}")
      end

      sig { returns(String) }
      def self.package_description
        check_label.downcase
      end

      sig { returns(T::Boolean) }
      def self.dump_supported?
        true
      end

      sig { returns(String) }
      def self.dump_disable_description
        "`dump` without #{banner_name}."
      end

      sig { returns(Symbol) }
      def self.dump_disable_env
        :"bundle_dump_no_#{type}"
      end

      sig { returns(T::Boolean) }
      def self.dump_disable_supported?
        true
      end

      sig { returns(Symbol) }
      def self.dump_disable_predicate_method
        :"no_#{type}?"
      end

      sig { returns(T::Boolean) }
      def self.add_supported?
        true
      end

      sig { returns(T::Boolean) }
      def self.remove_supported?
        true
      end

      sig { returns(T::Boolean) }
      def self.install_supported?
        true
      end

      sig { returns(T.nilable(String)) }
      def self.cleanup_heading
        nil
      end

      sig { returns(T::Boolean) }
      def self.cleanup_supported?
        !cleanup_heading.nil?
      end

      sig { abstract.void }
      def self.reset!; end

      # TODO: Replace these `T.untyped` package collections once extensions can
      # share a typed package interface without breaking Sorbet override checks.
      sig { abstract.returns(T::Array[T.untyped]) }
      def self.packages; end

      sig { abstract.returns(T::Array[T.untyped]) }
      def self.installed_packages; end

      sig { params(package: Object).returns(String) }
      def self.dump_entry(package)
        line = "#{type} #{quote(dump_name(package))}"
        with = dump_with(package)
        return line if with.blank?

        formatted_with = with.map { |requirement| quote(requirement) }.join(", ")
        "#{line}, with: [#{formatted_with}]"
      end

      sig { params(value: String).returns(String) }
      def self.quote(value)
        value.inspect
      end

      sig { params(package: Object).returns(String) }
      def self.dump_name(package)
        package.to_s
      end

      sig { params(_package: Object).returns(T.nilable(T::Array[String])) }
      def self.dump_with(_package)
        nil
      end

      sig { returns(String) }
      def self.dump
        packages.map { |package| dump_entry(package) }.join("\n")
      end

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

      sig { params(_entries: T::Array[Object]).returns(T::Array[String]) }
      def self.cleanup_items(_entries)
        []
      end

      sig { returns(T.nilable(Symbol)) }
      def self.legacy_cleanup_method
        nil
      end

      sig { params(_items: T::Array[String]).void }
      def self.cleanup!(_items); end

      sig { params(name: String, with: T.nilable(T::Array[String])).returns(Object) }
      def self.package_record(name, with: nil)
        _ = with

        name
      end

      sig { params(name: String, with: T.nilable(T::Array[String])).returns(T::Boolean) }
      def self.package_installed?(name, with: nil)
        installed_packages.include?(package_record(name, with:))
      end

      sig {
        params(
          name:       String,
          with:       T.nilable(T::Array[String]),
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
        ).returns(T::Boolean)
      }
      def self.preinstall!(name, with: nil, no_upgrade: false, verbose: false)
        _ = no_upgrade

        unless package_manager_installed?
          puts "Installing #{package_manager_name}. It is not currently installed." if verbose
          Bundle.system(HOMEBREW_BREW_FILE, "install", "--formula", package_manager_name, verbose:)
          # `formula_versions_from_env` consumes the env vars once at startup, so
          # keep the cached values across reset when bootstrapping a manager.
          formula_versions_from_env = T.let(
            Bundle.formula_versions_from_env_cache,
            T.nilable(T::Hash[String, String]),
          )
          upgrade_formulae = Bundle.upgrade_formulae
          Bundle.reset!
          Bundle.formula_versions_from_env_cache = formula_versions_from_env
          Bundle.upgrade_formulae = upgrade_formulae.join(",")
          unless package_manager_installed?
            raise "Unable to install #{name} #{package_description}. " \
                  "#{package_manager_name} installation failed."
          end
        end

        if package_installed?(name, with:)
          puts "Skipping install of #{name} #{package_description}. It is already installed." if verbose
          return false
        end

        true
      end

      sig {
        params(
          name:       String,
          with:       T.nilable(T::Array[String]),
          preinstall: T::Boolean,
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
        ).returns(T::Boolean)
      }
      def self.install!(name, with: nil, preinstall: true, no_upgrade: false, verbose: false, force: false)
        _ = no_upgrade
        _ = force

        return true unless preinstall

        puts "Installing #{name} #{package_description}. It is not currently installed." if verbose
        return false unless install_package!(name, with:, verbose:)

        package = package_record(name, with:)
        installed_packages << package unless installed_packages.include?(package)
        packages << package unless packages.include?(package)
        true
      end

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(String) }
      def failure_reason(package, no_upgrade:)
        "#{self.class.check_label} #{self.class.dump_name(package)} needs to be installed."
      end

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(package, no_upgrade: false)
        self.class.package_installed?(self.class.dump_name(package), with: self.class.dump_with(package))
      end

      sig {
        overridable.params(
          name:    String,
          with:    T.nilable(T::Array[String]),
          verbose: T::Boolean,
        ).returns(T::Boolean)
      }
      def self.install_package!(name, with: nil, verbose: false)
        _ = name
        _ = with
        _ = verbose

        raise NotImplementedError, "#{self} must override `install_package!` or `install!`."
      end
    end

    class << self
      sig { params(extension: T.class_of(Extension)).void }
      def register_extension(extension)
        @extensions ||= T.let([], T.nilable(T::Array[T.class_of(Extension)]))
        @extensions.reject! { |registered| registered.name == extension.name }
        @extensions << extension
      end

      sig { returns(T::Array[T.class_of(Extension)]) }
      def extensions
        @extensions ||= T.let([], T.nilable(T::Array[T.class_of(Extension)]))
        @extensions
      end

      sig { params(type: T.any(Symbol, String)).returns(T.nilable(T.class_of(Extension))) }
      def extension(type)
        requested_type = type.to_sym
        extensions.find { |registered| registered.type == requested_type }
      end
    end
  end
end
