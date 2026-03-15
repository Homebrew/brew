# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"

module Homebrew
  module Bundle
    class MacAppStore < Extension
      App = T.type_alias { { id: String, name: String } }

      PACKAGE_TYPE = :mas
      PACKAGE_TYPE_NAME = "App"
      BANNER_NAME = "Mac App Store dependencies"

      class << self
        sig { override.returns(T::Boolean) }
        def add_supported?
          false
        end

        sig { override.returns(T::Boolean) }
        def dump_disable_supported?
          false
        end

        sig { override.params(name: String, options: Homebrew::Bundle::Extension::EntryOptions).returns(Dsl::Entry) }
        def entry(name, options = {})
          id = options[:id]
          raise "options[:id](#{id}) should be an Integer object" unless id.is_a? Integer

          Dsl::Entry.new(type, name, id:)
        end

        sig { override.void }
        def reset!
          @apps = T.let(nil, T.nilable(T::Array[[String, String]]))
          @packages = T.let(nil, T.nilable(T::Array[App]))
          @installed_app_ids = T.let(nil, T.nilable(T::Array[String]))
          @outdated_app_ids = T.let(nil, T.nilable(T::Array[String]))
        end

        sig { returns(T::Array[[String, String]]) }
        def apps
          apps = @apps
          return apps if apps

          @apps = if Bundle.mas_installed?
            mas = Bundle.which_mas
            return [] if mas.nil?

            `#{mas} list 2>/dev/null`.split("\n").filter_map do |app|
              app_details = app.match(/\A\s*(?<id>\d+)\s+(?<name>.*?)\s+\((?<version>[\d.]*)\)\Z/)
              next if app_details.nil?

              id = app_details[:id]
              name = app_details[:name]
              next if id.nil? || name.nil?

              # Only add the application details should we have a valid match.
              # Strip unprintable characters
              [id, name.gsub(/[[:cntrl:]]|\p{C}/, "")]
            end
          else
            []
          end
        end

        sig { returns(T::Array[String]) }
        def app_ids
          apps.map(&:first)
        end

        sig { override.returns(T::Array[App]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = apps.sort_by { |_, name| name.downcase }.map { |id, name| { id:, name: } }
        end

        sig { override.returns(T::Array[App]) }
        def installed_packages
          packages
        end

        sig { returns(T::Array[String]) }
        def installed_app_ids
          installed_app_ids = @installed_app_ids
          return installed_app_ids if installed_app_ids

          @installed_app_ids = app_ids
        end

        sig { override.params(package: Object).returns(String) }
        def dump_entry(package)
          app = T.cast(package, App)
          "mas #{quote(app[:name])}, id: #{app[:id]}"
        end

        sig { params(id: Integer).returns(T::Boolean) }
        def app_id_installed?(id)
          installed_app_ids.any? { |app_id| app_id.to_i == id }
        end

        sig { params(id: Integer).returns(T::Boolean) }
        def app_id_upgradable?(id)
          outdated_app_ids.any? { |app_id| app_id.to_i == id }
        end

        sig { params(id: Integer, no_upgrade: T::Boolean).returns(T::Boolean) }
        def app_id_installed_and_up_to_date?(id, no_upgrade: false)
          return false unless app_id_installed?(id)
          return true if no_upgrade

          !app_id_upgradable?(id)
        end

        sig { returns(T::Array[String]) }
        def outdated_app_ids
          outdated_app_ids = @outdated_app_ids
          return outdated_app_ids if outdated_app_ids

          @outdated_app_ids = if Bundle.mas_installed?
            mas = Bundle.which_mas
            return [] if mas.nil?

            `#{mas} outdated 2>/dev/null`.split("\n").map do |app|
              app.split(" ", 2).first.to_s
            end
          else
            []
          end
        end

        sig {
          params(
            name:       String,
            id:         T.nilable(Integer),
            with:       T.nilable(T::Array[String]),
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            options:    Object,
          ).returns(T::Boolean)
        }
        def preinstall!(name, id = nil, with: nil, no_upgrade: false, verbose: false, **options)
          _ = with
          id ||= T.cast(options[:id], T.nilable(Integer))
          raise ArgumentError, "missing keyword: id" if id.nil?

          unless Bundle.mas_installed?
            puts "Installing mas. It is not currently installed." if verbose
            Bundle.system(HOMEBREW_BREW_FILE, "install", "mas", verbose:)
            raise "Unable to install #{name} app. mas installation failed." unless Bundle.mas_installed?
          end

          if app_id_installed?(id) &&
             (no_upgrade || !app_id_upgradable?(id))
            puts "Skipping install of #{name} app. It is already installed." if verbose
            return false
          end

          true
        end

        sig {
          params(
            name:       String,
            id:         T.nilable(Integer),
            with:       T.nilable(T::Array[String]),
            preinstall: T::Boolean,
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            force:      T::Boolean,
            options:    Object,
          ).returns(T::Boolean)
        }
        def install!(name, id = nil, with: nil, preinstall: true, no_upgrade: false, verbose: false, force: false,
                     **options)
          _ = with
          id ||= T.cast(options[:id], T.nilable(Integer))
          raise ArgumentError, "missing keyword: id" if id.nil?

          _ = no_upgrade
          _ = force

          return true unless preinstall

          mas = Bundle.which_mas
          return false if mas.nil?

          if app_id_installed?(id)
            puts "Upgrading #{name} app. It is installed but not up-to-date." if verbose
            return false unless Bundle.system(mas, "upgrade", id.to_s, verbose:)

            return true
          end

          puts "Installing #{name} app. It is not currently installed." if verbose
          return false unless Bundle.system(mas, "get", id.to_s, verbose:)

          apps << [id.to_s, name] unless apps.any? { |app_id, _app_name| app_id.to_i == id }
          packages << { id: id.to_s, name: } unless packages.any? { |app| app[:id].to_i == id }
          installed_app_ids << id.to_s unless installed_app_ids.include?(id.to_s)
          true
        end
      end

      sig { override.params(entries: T::Array[Object]).returns(T.untyped) }
      def format_checkable(entries)
        checkable_entries(entries).to_h do |entry|
          entry = T.cast(entry, Dsl::Entry)
          [T.cast(entry.options.fetch(:id), Integer), entry.name]
        end
      end

      sig { override.params(packages: T.untyped, no_upgrade: T::Boolean).returns(T::Array[T.untyped]) }
      def exit_early_check(packages, no_upgrade:)
        work_to_be_done = packages.find do |id, _name|
          !installed_and_up_to_date?(id, no_upgrade:)
        end

        Array(work_to_be_done)
      end

      sig { override.params(packages: T.untyped, no_upgrade: T::Boolean).returns(T::Array[String]) }
      def full_check(packages, no_upgrade:)
        packages.reject { |id, _name| installed_and_up_to_date?(id, no_upgrade:) }
                .map { |_id, name| failure_reason(name, no_upgrade:) }
      end

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(String) }
      def failure_reason(package, no_upgrade:)
        reason = if no_upgrade && Bundle.upgrade_formulae.exclude?(T.cast(package, String))
          "needs to be installed."
        else
          "needs to be installed or updated."
        end
        "#{self.class.check_label} #{package} #{reason}"
      end

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(package, no_upgrade: false)
        self.class.app_id_installed_and_up_to_date?(T.cast(package, Integer), no_upgrade:)
      end
    end

    # TODO: Remove these compatibility aliases once bundle callers and tests
    # stop requiring separate Mac App Store dumper/installer/checker constants.
    MacAppStoreDumper = MacAppStore
    MacAppStoreInstaller = MacAppStore

    module Checker
      # TODO: Remove this compatibility alias once bundle callers and tests stop
      # requiring a separate Mac App Store checker constant.
      MacAppStoreChecker = Homebrew::Bundle::MacAppStore
    end
  end
end
