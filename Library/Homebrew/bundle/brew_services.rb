# typed: true # rubocop:todo Sorbet/StrictSigil
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
          def reset!
            @started_services = nil
          end

          def stop(name, keep: false, verbose: false)
            return true unless started?(name)

            args = ["services", "stop", name]
            args << "--keep" if keep
            return unless Bundle.brew(*args, verbose:)

            started_services.delete(name)
            true
          end

          def start(name, file: nil, verbose: false)
            args = ["services", "start", name]
            args << "--file=#{file}" if file
            return unless Bundle.brew(*args, verbose:)

            started_services << name
            true
          end

          def run(name, file: nil, verbose: false)
            args = ["services", "run", name]
            args << "--file=#{file}" if file
            return unless Bundle.brew(*args, verbose:)

            started_services << name
            true
          end

          def restart(name, file: nil, verbose: false)
            args = ["services", "restart", name]
            args << "--file=#{file}" if file
            return unless Bundle.brew(*args, verbose:)

            started_services << name
            true
          end

          def started?(name)
            started_services.include? name
          end

          def started_services
            @started_services ||= if !Homebrew::Services::System.launchctl? && !Homebrew::Services::System.systemctl?
              opoo "Skipping `brew services list` due to missing launchctl/systemctl"
              []
            else
              states_to_skip = %w[stopped none]

              services_list = JSON.parse(Utils.safe_popen_read(HOMEBREW_BREW_FILE, "services", "list", "--json"))
              services_list.filter_map do |hash|
                hash.fetch("name") if states_to_skip.exclude?(hash.fetch("status"))
              end
            end
          end

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

        def failure_reason(name, no_upgrade:)
          _ = no_upgrade

          "Service #{name} needs to be started."
        end

        def installed_and_up_to_date?(formula, no_upgrade: false)
          _ = no_upgrade

          return true unless formula_needs_to_start?(entry_to_formula(formula))
          return true if self.class.started?(formula.name)

          old_name = lookup_old_name(formula.name)
          return true if old_name && self.class.started?(old_name)

          false
        end

        def entry_to_formula(entry)
          Homebrew::Bundle::Brew.new(entry.name, entry.options)
        end

        def formula_needs_to_start?(formula)
          formula.start_service? || formula.restart_service?
        end

        def lookup_old_name(service_name)
          @old_names ||= Homebrew::Bundle::Brew.formula_oldnames
          old_name = @old_names[service_name]
          old_name ||= @old_names[service_name.split("/").last]
          old_name
        end

        def format_checkable(entries)
          checkable_entries(entries)
        end
      end
    end
  end
end
