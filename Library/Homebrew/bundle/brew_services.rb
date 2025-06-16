# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "services/system"

module Homebrew
  module Bundle
    module BrewServices
      def self.reset!
        @started_services = nil
      end

      def self.stop(name, keep: false, verbose: false)
        return true unless started?(name)

        args = ["services", "stop", name]
        args << "--keep" if keep
        return unless Bundle.brew(*args, verbose:)

        started_services.delete(name)
        true
      end

      def self.start(name, file: nil, verbose: false)
        args = ["services", "start", name]
        args << "--file=#{file}" if file
        return unless Bundle.brew(*args, verbose:)

        started_services << name
        true
      end

      def self.run(name, file: nil, verbose: false)
        args = ["services", "run", name]
        args << "--file=#{file}" if file
        return unless Bundle.brew(*args, verbose:)

        started_services << name
        true
      end

      def self.restart(name, file: nil, verbose: false)
        args = ["services", "restart", name]
        args << "--file=#{file}" if file
        return unless Bundle.brew(*args, verbose:)

        started_services << name
        true
      end

      def self.started?(name)
        started_services.include? name
      end

      def self.started_services
        @started_services ||= begin
          states_to_skip = %w[stopped none]
          Utils.safe_popen_read(HOMEBREW_BREW_FILE, "services", "list").lines.filter_map do |line|
            name, state, _plist = line.split(/\s+/)
            next if states_to_skip.include? state

            name
          end
        end
      end

      def self.versioned_service_file(name)
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
  end
end
