# typed: strict
# frozen_string_literal: true

require "bundle/checker"

module Homebrew
  module Bundle
    module Checker
      class FlatpakChecker < Homebrew::Bundle::Checker::Base
        PACKAGE_TYPE = :flatpak
        PACKAGE_TYPE_NAME = "Flatpak"

        sig {
          params(entries: T::Array[Homebrew::Bundle::Dsl::Entry], exit_on_first_error: T::Boolean,
                 no_upgrade: T::Boolean, verbose: T::Boolean).returns(T::Array[String])
        }
        def find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
          super
        end

        # Override to return entry hashes with options instead of just names
        sig { params(entries: T::Array[Bundle::Dsl::Entry]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def format_checkable(entries)
          checkable_entries(entries).map do |entry|
            { name: entry.name, options: entry.options || {} }
          end
        end

        sig { params(package: T.any(String, T::Hash[Symbol, T.untyped]), no_upgrade: T::Boolean).returns(String) }
        def failure_reason(package, no_upgrade:)
          name = package.is_a?(Hash) ? package[:name] : package
          "#{PACKAGE_TYPE_NAME} #{name} needs to be installed."
        end

        sig {
          params(package: T.any(String, T::Hash[Symbol, T.untyped]), no_upgrade: T::Boolean).returns(T::Boolean)
        }
        def installed_and_up_to_date?(package, no_upgrade: false)
          require "bundle/flatpak_installer"

          if package.is_a?(Hash)
            name = package[:name]
            remote = package.dig(:options, :remote) || "flathub"
            url = package.dig(:options, :url)

            # 3-tier remote handling:
            # - Tier 1: Named remote → check with that remote name
            # - Tier 2: URL only → resolve to single-app remote name (<app-id>-origin)
            # - Tier 3: URL + name → check with the named remote
            actual_remote = if url.blank? && remote.start_with?("http://", "https://")
              # Tier 2: URL only - resolve to single-app remote name
              # (.flatpakref - check by name only since remote name varies)
              return Homebrew::Bundle::FlatpakInstaller.package_installed?(name) if remote.end_with?(".flatpakref")

              Homebrew::Bundle::FlatpakInstaller.generate_single_app_remote_name(name)
            else
              # Tier 1 (named remote) and Tier 3 (named remote with URL) both use the remote name
              remote
            end

            Homebrew::Bundle::FlatpakInstaller.package_installed?(name, remote: actual_remote)
          else
            # If just a string, check without remote
            Homebrew::Bundle::FlatpakInstaller.package_installed?(package)
          end
        end
      end
    end
  end
end
