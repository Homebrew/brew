# typed: strict
# frozen_string_literal: true

require "services/system"
require "utils/output"
require "bundle/brew"

module Homebrew
  module Bundle
    class Brew
      class Services < Homebrew::Bundle::Brew
        extend Utils::Output::Mixin

        class << self
          sig { override.void }
          def reset!
            @started_services = T.let(nil, T.nilable(T::Array[String]))
          end

          sig { params(name: String, keep: T::Boolean, verbose: T::Boolean).returns(T.nilable(T::Boolean)) }
          def stop(name, keep: false, verbose: false)
            return true unless started?(name)

            args = ["services", "stop", name]
            args << "--keep" if keep
            return unless Bundle.brew(*args, verbose:)

            started_services.delete(name)
            true
          end

          sig { params(name: String, file: T.nilable(Pathname), verbose: T::Boolean).returns(T.nilable(T::Boolean)) }
          def start(name, file: nil, verbose: false)
            args = ["services", "start", name]
            args << "--file=#{file}" if file
            return unless Bundle.brew(*args, verbose:)

            started_services << name
            true
          end

          sig { params(name: String, file: T.nilable(Pathname), verbose: T::Boolean).returns(T.nilable(T::Boolean)) }
          def run(name, file: nil, verbose: false)
            args = ["services", "run", name]
            args << "--file=#{file}" if file
            return unless Bundle.brew(*args, verbose:)

            started_services << name
            true
          end

          sig { params(name: String, file: T.nilable(Pathname), verbose: T::Boolean).returns(T.nilable(T::Boolean)) }
          def restart(name, file: nil, verbose: false)
            args = ["services", "restart", name]
            args << "--file=#{file}" if file
            return unless Bundle.brew(*args, verbose:)

            started_services << name
            true
          end

          sig { params(name: String).returns(T::Boolean) }
          def started?(name)
            started_services.include? name
          end

          sig { returns(T::Array[String]) }
          def started_services
            @started_services ||= begin
              if !Homebrew::Services::System.launchctl? && !Homebrew::Services::System.systemctl?
                odie Homebrew::Services::System::MISSING_DAEMON_MANAGER_EXCEPTION_MESSAGE
              end
              states_to_skip = %w[stopped none]
              Utils.safe_popen_read(HOMEBREW_BREW_FILE, "services", "list").lines.filter_map do |line|
                name, state, _plist = line.split(/\s+/)
                next if states_to_skip.include? state

                name
              end
            end
          end

          sig { params(name: String).returns(T.nilable(Pathname)) }
          def versioned_service_file(name)
            env_version = Bundle.formula_versions_from_env(name)
            return if env_version.nil?

            formula = Formula[name]
            prefix = formula.rack/env_version
            return unless prefix.directory?

            service_file = if Homebrew::Services::System.launchctl?
              prefix/"#{formula.plist_name}.plist"
            else
              prefix/"#{formula.service_name}.service"
            end

            service_file if service_file.file?
          end
        end

        sig { override.params(name: Object, no_upgrade: T::Boolean).returns(String) }
        def failure_reason(name, no_upgrade:)
          _ = no_upgrade

          "Service #{name} needs to be started."
        end

        sig { override.params(formula: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
        def installed_and_up_to_date?(formula, no_upgrade: false)
          _ = no_upgrade
          formula = T.cast(formula, Homebrew::Bundle::Dsl::Entry)

          return true unless formula_needs_to_start?(entry_to_formula(formula))
          return true if self.class.started?(formula.name)

          old_name = lookup_old_name(formula.name)
          return true if old_name && self.class.started?(old_name)

          false
        end

        sig { params(entry: Homebrew::Bundle::Dsl::Entry).returns(Homebrew::Bundle::Brew) }
        def entry_to_formula(entry)
          Homebrew::Bundle::Brew.new(entry.name, entry.options)
        end

        sig { params(formula: Homebrew::Bundle::Brew).returns(T::Boolean) }
        def formula_needs_to_start?(formula)
          formula.start_service? || formula.restart_service?
        end

        sig { params(service_name: String).returns(T.nilable(String)) }
        def lookup_old_name(service_name)
          @old_names ||= T.let(nil, T.nilable(T::Hash[String, String]))
          @old_names ||= Homebrew::Bundle::Brew.formula_oldnames
          old_name = @old_names[service_name]
          old_name ||= @old_names[service_name.split("/").last]
          old_name
        end

        sig { override.params(entries: T::Array[Object]).returns(T::Array[Object]) }
        def format_checkable(entries)
          checkable_entries(entries)
        end
      end
    end
  end
end
