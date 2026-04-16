# typed: strict
# frozen_string_literal: true

require "bundle/package_type"

module Homebrew
  module Bundle
    ExtensionTypes = T.type_alias { T::Hash[Symbol, T::Boolean] }

    class Extension < Homebrew::Bundle::PackageType
      extend T::Helpers

      abstract!

      sig { override.params(subclass: T.class_of(Homebrew::Bundle::PackageType)).void }
      def self.inherited(subclass)
        super
        Homebrew::Bundle.register_extension(T.cast(subclass, T.class_of(Homebrew::Bundle::Extension)))
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

      sig { params(name: String, options: Homebrew::Bundle::EntryInputOptions).returns(Dsl::Entry) }
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

      sig { returns(T::Boolean) }
      def self.package_manager_installed?
        package_manager_executable.present?
      end

      sig { returns(T.nilable(Pathname)) }
      def self.package_manager_executable
        which(package_manager_name, ORIGINAL_PATHS)
      end

      sig { returns(Pathname) }
      def self.package_manager_executable!
        package_manager_executable || raise("#{package_manager_name} is not installed")
      end

      sig { params(executable: Pathname).returns(T::Hash[String, String]) }
      def self.package_manager_env(executable)
        { "PATH" => "#{executable.dirname}:#{ORIGINAL_PATHS.join(":")}" }
      end

      sig {
        type_parameters(:U)
          .params(_blk: T.proc.params(executable: Pathname).returns(T.type_parameter(:U)))
          .returns(T.type_parameter(:U))
      }
      def self.with_package_manager_env(&_blk)
        executable = package_manager_executable!
        with_env(package_manager_env(executable)) { yield executable }
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

      sig { override.params(_name: String, _options: Homebrew::Bundle::EntryOptions).returns(String) }
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

      sig { override.returns(String) }
      def self.dump
        packages.map { |package| dump_entry(package) }.join("\n")
      end

      sig { params(describe: T::Boolean, no_restart: T::Boolean).returns(String) }
      def self.dump_output(describe: false, no_restart: false)
        _ = describe
        _ = no_restart

        dump
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

      sig { params(entries: T::Array[Dsl::Entry]).returns(T::Array[String]) }
      def self.cleanup_items(entries)
        return [].freeze unless package_manager_installed?

        kept_packages = entries.filter_map do |entry|
          entry.name if entry.type == type
        end

        return [].freeze if kept_packages.empty?

        installed_names = packages.map { |pkg| dump_name(pkg) }
        installed_names - kept_packages
      end

      sig { returns(Symbol) }
      def self.legacy_check_step
        :registered_extensions_to_install
      end

      sig { params(items: T::Array[String]).void }
      def self.cleanup!(items)
        executable = package_manager_executable
        return if executable.nil?

        with_env(package_manager_env(executable)) do
          items.each do |name|
            uninstall_package!(name, executable:)
          end
        end
        puts "Uninstalled #{items.size} #{banner_name}#{"s" if items.size != 1}"
      end

      sig { params(name: String, executable: Pathname).void }
      def self.uninstall_package!(name, executable: Pathname.new(""))
        raise NotImplementedError, "#{self} must override `uninstall_package!` or `cleanup!`."
      end

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
        override.params(
          name:       String,
          with:       T.nilable(T::Array[String]),
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          _options:   Homebrew::Bundle::EntryOption,
        ).returns(T::Boolean)
      }
      def self.preinstall!(name, with: nil, no_upgrade: false, verbose: false, **_options)
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
        override.params(
          name:       String,
          with:       T.nilable(T::Array[String]),
          preinstall: T::Boolean,
          no_upgrade: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          _options:   Homebrew::Bundle::EntryOption,
        ).returns(T::Boolean)
      }
      def self.install!(name, with: nil, preinstall: true, no_upgrade: false, verbose: false, force: false,
                        **_options)
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

      sig {
        params(
          type: T.any(Symbol, String),
        ).returns(T.nilable(T.class_of(PackageType)))
      }
      def installable(type)
        package_type(type) || extension(type)
      end
    end
  end
end
