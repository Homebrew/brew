# typed: strict
# frozen_string_literal: true

require "formula"
require "services/system"

module Homebrew
  module Bundle
    module Services
      sig {
        params(
          entries: T::Array[Homebrew::Bundle::Dsl::Entry],
          _block:  T.proc.params(info: T::Hash[String, T.anything], service_file: Pathname).void,
        ).void
      }
      private_class_method def self.map_entries(entries, &_block)
        formula_versions = Bundle.formula_version_map

        entries.filter_map do |entry|
          next if entry.type != :brew

          formula = Formula[entry.name]
          next unless formula.any_version_installed?

          version = formula_versions[entry.name.downcase]
          prefix = formula.rack/version if version

          service_file = if prefix&.directory?
            if Homebrew::Services::System.launchctl?
              prefix/"#{formula.plist_name}.plist"
            else
              prefix/"#{formula.service_name}.service"
            end
          end

          unless service_file&.file?
            prefix = formula.any_installed_prefix
            next if prefix.nil?

            service_file = if Homebrew::Services::System.launchctl?
              prefix/"#{formula.plist_name}.plist"
            else
              prefix/"#{formula.service_name}.service"
            end
          end

          next unless service_file.file?

          # We parse from a command invocation so that brew wrappers can invoke special actions
          # for the elevated nature of `brew services`
          output = Utils.safe_popen_read(HOMEBREW_BREW_FILE, "services", "info", "--json", formula.full_name)
          info = JSON.parse(output)

          raise "Failed to get service info for #{entry.name}" if info.length != 1

          yield info.first, service_file
        end
      end

      sig { params(entries: T::Array[Homebrew::Bundle::Dsl::Entry]).void }
      def self.run(entries)
        map_entries(entries) do |info, service_file|
          next if info["running"]

          safe_system HOMEBREW_BREW_FILE, "services", "run", "--file=#{service_file}", info["name"]
        end
      end

      sig { params(entries: T::Array[Homebrew::Bundle::Dsl::Entry]).void }
      def self.stop(entries)
        map_entries(entries) do |info, _service_file|
          next unless info["loaded"]

          # Try avoid services not started by `brew bundle services`
          next if Homebrew::Services::System.launchctl? && info["registered"]

          safe_system HOMEBREW_BREW_FILE, "services", "stop", info["name"]
        end
      end
    end
  end
end
