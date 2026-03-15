# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"

module Homebrew
  module Bundle
    class Flatpak < Extension
      Package = T.type_alias { { name: String, remote: String, remote_url: T.nilable(String) } }

      PACKAGE_TYPE = :flatpak
      PACKAGE_TYPE_NAME = "Flatpak"
      BANNER_NAME = "Flatpak packages"

      class << self
        sig { override.returns(String) }
        def switch_description
          "#{super} Note: Linux only."
        end

        sig { override.returns(T.nilable(String)) }
        def cleanup_heading
          "flatpaks"
        end

        sig { override.returns(T.nilable(Symbol)) }
        def legacy_cleanup_method
          # TODO: Remove this legacy cleanup hook once the direct cleanup specs
          # stop stubbing the old command-level flatpak helper.
          :flatpaks_to_uninstall
        end

        sig { override.params(name: String, options: Homebrew::Bundle::Extension::EntryOptions).returns(Dsl::Entry) }
        def entry(name, options = {})
          unknown_options = options.keys - [:remote, :url]
          raise "unknown options(#{unknown_options.inspect}) for flatpak" if unknown_options.present?

          remote = options[:remote]
          url = options[:url]
          if !remote.nil? && !remote.is_a?(String)
            raise "options[:remote](#{remote.inspect}) should be a String object"
          end
          raise "options[:url](#{url.inspect}) should be a String object" if !url.nil? && !url.is_a?(String)

          # Validate: url: can only be used with a named remote (not a URL remote)
          if url && remote&.start_with?("http://", "https://")
            raise "url: parameter cannot be used when remote: is already a URL"
          end

          normalized_options = {}
          normalized_options[:remote] = remote || "flathub"
          normalized_options[:url] = url if url

          Dsl::Entry.new(type, name, normalized_options)
        end

        sig { override.void }
        def reset!
          @packages = T.let(nil, T.nilable(T::Array[String]))
          @packages_with_remotes = T.let(nil, T.nilable(T::Array[Package]))
          @remote_urls = T.let(nil, T.nilable(T::Hash[String, String]))
          @installed_packages = T.let(nil, T.nilable(T::Array[Package]))
        end

        sig { returns(T::Hash[String, String]) }
        def remote_urls
          remote_urls = @remote_urls
          return remote_urls if remote_urls

          @remote_urls = if Bundle.flatpak_installed?
            flatpak = Bundle.which_flatpak
            return {} if flatpak.nil?

            output = `#{flatpak} remote-list --system --columns=name,url 2>/dev/null`.chomp
            urls = {}
            output.split("\n").each do |line|
              parts = line.strip.split("\t")
              next if parts.size < 2

              name = parts[0]
              url = parts[1]
              urls[name] = url if name && url
            end
            urls
          else
            {}
          end
        end

        sig { returns(T::Array[Package]) }
        def packages_with_remotes
          packages_with_remotes = @packages_with_remotes
          return packages_with_remotes if packages_with_remotes

          @packages_with_remotes = if Bundle.flatpak_installed?
            flatpak = Bundle.which_flatpak
            return [] if flatpak.nil?

            # List applications with their origin remote
            # Using --app to filter applications only
            # Using --columns=application,origin to get app IDs and their remotes
            output = `#{flatpak} list --app --columns=application,origin 2>/dev/null`.chomp

            packages = output.split("\n").filter_map do |line|
              parts = line.strip.split("\t")
              name = parts[0]
              next if parts.empty? || name.nil? || name.empty?

              remote = parts[1] || "flathub"
              package = T.let({ name:, remote:, remote_url: T.let(nil, T.nilable(String)) }, Package)
              remote_url = remote_urls[remote]
              package[:remote_url] = remote_url
              package
            end
            packages.sort_by { |pkg| pkg[:name].to_s }
          else
            []
          end
        end

        sig { override.returns(T::Array[String]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = packages_with_remotes.map { |pkg| pkg[:name] }
        end

        sig { override.returns(T::Array[Package]) }
        def installed_packages
          installed_packages = @installed_packages
          return installed_packages if installed_packages

          @installed_packages = packages_with_remotes.dup
        end

        sig { override.params(package: Object).returns(String) }
        def dump_entry(package)
          package = T.cast(package, Package)
          remote = package[:remote]
          remote_url = package[:remote_url]
          name = package[:name]

          if remote == "flathub"
            # Tier 1: Don't specify remote for flathub (default)
            "flatpak #{quote(name)}"
          elsif remote&.end_with?("-origin")
            # Tier 2: Single-app remote - dump with URL only
            if remote_url.present?
              "flatpak #{quote(name)}, remote: #{quote(remote_url)}"
            else
              # Fallback if URL not available (shouldn't happen for -origin remotes)
              "flatpak #{quote(name)}, remote: #{quote(remote)}"
            end
          elsif remote_url.present?
            # Tier 3: Named shared remote - dump with name and URL
            "flatpak #{quote(name)}, remote: #{quote(remote)}, url: #{quote(remote_url)}"
          else
            # Named remote without URL (user-defined or system remote)
            "flatpak #{quote(name)}, remote: #{quote(remote)}"
          end
        end

        sig { override.returns(String) }
        def dump
          packages_with_remotes.map { |package| dump_entry(package) }.join("\n")
        end

        sig {
          override.params(
            name:       String,
            with:       T.nilable(T::Array[String]),
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            remote:     String,
            url:        T.nilable(String),
            _options:   T.anything,
          ).returns(T::Boolean)
        }
        def preinstall!(name, with: nil, no_upgrade: false, verbose: false, remote: "flathub", url: nil, **_options)
          _ = with
          _ = no_upgrade
          _ = url

          return false unless Bundle.flatpak_installed?

          # Check if package is installed at all (regardless of remote)
          if package_installed?(name)
            puts "Skipping install of #{name} Flatpak. It is already installed." if verbose
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
            remote:     String,
            url:        T.nilable(String),
            _options:   T.anything,
          ).returns(T::Boolean)
        }
        def install!(name, with: nil, preinstall: true, no_upgrade: false, verbose: false, force: false,
                     remote: "flathub", url: nil, **_options)
          _ = with
          _ = no_upgrade
          _ = force

          return true unless Bundle.flatpak_installed?
          return true unless preinstall

          flatpak = Bundle.which_flatpak.to_s

          # 3-tier remote handling:
          # - Tier 1: no URL → use named remote (default: flathub)
          # - Tier 2: URL only → single-app remote (<app-id>-origin)
          # - Tier 3: URL + name → named shared remote

          if url.present?
            # Tier 3: Named remote with URL - create shared remote
            puts "Installing #{name} Flatpak from #{remote} (#{url}). It is not currently installed." if verbose
            ensure_named_remote_exists!(flatpak, remote, url, verbose:)
            actual_remote = remote
          elsif remote.start_with?("http://", "https://")
            if remote.end_with?(".flatpakref")
              # .flatpakref files - install directly (Flatpak handles single-app remote natively)
              puts "Installing #{name} Flatpak from #{remote}. It is not currently installed." if verbose
              return install_flatpakref!(flatpak, name, remote, verbose:)
            else
              # Tier 2: URL only - create single-app remote
              actual_remote = generate_single_app_remote_name(name)
              if verbose
                puts "Installing #{name} Flatpak from #{actual_remote} (#{remote}). It is not currently installed."
              end
              ensure_single_app_remote_exists!(flatpak, actual_remote, remote, verbose:)
            end
          else
            # Tier 1: Named remote (default: flathub)
            puts "Installing #{name} Flatpak from #{remote}. It is not currently installed." if verbose
            actual_remote = remote
          end

          # Install from the remote
          return false unless Bundle.system(flatpak, "install", "-y", "--system", actual_remote, name, verbose:)

          package = { name:, remote: actual_remote, remote_url: url }
          packages_with_remotes = T.let(@packages_with_remotes || [], T::Array[Package])
          packages_with_remotes << package
          @packages_with_remotes = packages_with_remotes
          @installed_packages = packages_with_remotes.dup
          @packages = packages_with_remotes.map { |pkg| pkg[:name] }
          true
        end

        # Install from a .flatpakref file (Tier 2 variant - Flatpak handles single-app remote natively)
        sig { params(flatpak: String, name: String, url: String, verbose: T::Boolean).returns(T::Boolean) }
        def install_flatpakref!(flatpak, name, url, verbose:)
          return false unless Bundle.system(flatpak, "install", "-y", "--system", url, verbose:)

          # Get the actual remote name used by Flatpak
          output = `#{flatpak} list --app --columns=application,origin 2>/dev/null`.chomp
          installed = output.split("\n").find { |line| line.start_with?(name) }
          actual_remote = installed ? installed.split("\t")[1] : "#{name}-origin"
          actual_remote ||= "#{name}-origin"
          package = { name:, remote: actual_remote, remote_url: nil }
          packages_with_remotes = T.let(@packages_with_remotes || [], T::Array[Package])
          packages_with_remotes << package
          @packages_with_remotes = packages_with_remotes
          @installed_packages = packages_with_remotes.dup
          @packages = packages_with_remotes.map { |pkg| pkg[:name] }
          true
        end

        # Generate a single-app remote name (Tier 2)
        # Pattern: <app-id>-origin (matches Flatpak's native behavior for .flatpakref)
        sig { params(app_id: String).returns(String) }
        def generate_single_app_remote_name(app_id)
          "#{app_id}-origin"
        end

        # Ensure a single-app remote exists (Tier 2)
        # Safe to replace if URL differs since it's isolated per-app
        sig { params(flatpak: String, remote_name: String, url: String, verbose: T::Boolean).void }
        def ensure_single_app_remote_exists!(flatpak, remote_name, url, verbose:)
          existing_url = get_remote_url(flatpak, remote_name)

          if existing_url && existing_url != url
            # Single-app remote with different URL - safe to replace
            puts "Replacing single-app remote #{remote_name} (URL changed)" if verbose
            Bundle.system(flatpak, "remote-delete", "--system", "--force", remote_name, verbose:)
            existing_url = nil
          end

          return if existing_url

          puts "Adding single-app remote #{remote_name} from #{url}" if verbose
          add_remote!(flatpak, remote_name, url, verbose:)
        end

        # Ensure a named shared remote exists (Tier 3)
        # Warn but don't change if URL differs (user explicitly named it)
        sig { params(flatpak: String, remote_name: String, url: String, verbose: T::Boolean).void }
        def ensure_named_remote_exists!(flatpak, remote_name, url, verbose:)
          existing_url = get_remote_url(flatpak, remote_name)

          if existing_url && existing_url != url
            # Named remote with different URL - warn but don't change (user explicitly named it)
            puts "Warning: Remote '#{remote_name}' exists with different URL (#{existing_url}), using existing"
            return
          end

          return if existing_url

          puts "Adding named remote #{remote_name} from #{url}" if verbose
          add_remote!(flatpak, remote_name, url, verbose:)
        end

        # Get URL for an existing remote, or nil if not found
        sig { params(flatpak: String, remote_name: String).returns(T.nilable(String)) }
        def get_remote_url(flatpak, remote_name)
          output = `#{flatpak} remote-list --system --columns=name,url 2>/dev/null`.chomp
          output.split("\n").each do |line|
            parts = line.split("\t")
            return parts[1] if parts[0] == remote_name
          end
          nil
        end

        # Add a remote with appropriate flags
        sig { params(flatpak: String, remote_name: String, url: String, verbose: T::Boolean).returns(T::Boolean) }
        def add_remote!(flatpak, remote_name, url, verbose:)
          if url.end_with?(".flatpakrepo")
            Bundle.system(flatpak, "remote-add", "--if-not-exists", "--system", remote_name, url, verbose:)
          else
            # For bare repository URLs, add with --no-gpg-verify for user repos
            Bundle.system(
              flatpak, "remote-add", "--if-not-exists", "--system", "--no-gpg-verify", remote_name, url, verbose:
            )
          end
        end

        sig {
          override.params(
            name:   String,
            with:   T.nilable(T::Array[String]),
            remote: T.nilable(String),
          ).returns(T::Boolean)
        }
        def package_installed?(name, with: nil, remote: nil)
          _ = with

          if remote
            installed_packages.any? { |pkg| pkg[:name] == name && pkg[:remote] == remote }
          else
            installed_packages.any? { |pkg| pkg[:name] == name }
          end
        end

        sig { params(entries: T::Array[Object]).returns(T::Array[String]) }
        def cleanup_items(entries)
          return [].freeze unless Bundle.flatpak_installed?

          kept_flatpaks = entries.filter_map do |entry|
            entry = T.cast(entry, Dsl::Entry)
            entry.name if entry.type == type
          end

          return [].freeze if kept_flatpaks.empty?

          packages - kept_flatpaks
        end

        sig { params(flatpaks: T::Array[String]).void }
        def cleanup!(flatpaks)
          flatpaks.each do |flatpak_name|
            Kernel.system("flatpak", "uninstall", "-y", "--system", flatpak_name)
          end
          puts "Uninstalled #{flatpaks.size} flatpak#{"s" if flatpaks.size != 1}"
        end
      end

      sig { override.params(entries: T::Array[Object]).returns(T::Array[Object]) }
      def format_checkable(entries)
        checkable_entries(entries).map do |entry|
          entry = T.cast(entry, Dsl::Entry)
          { name: entry.name, options: entry.options || {} }
        end
      end

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(String) }
      def failure_reason(package, no_upgrade:)
        _ = no_upgrade

        name = if package.is_a?(Hash)
          package[:name]
        else
          package
        end
        "#{self.class.check_label} #{name} needs to be installed."
      end

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(package, no_upgrade: false)
        _ = no_upgrade

        return self.class.package_installed?(T.cast(package, String)) unless package.is_a?(Hash)

        flatpak = package
        name = T.cast(flatpak[:name], String)
        options = T.cast(flatpak[:options], T::Hash[Symbol, String])
        remote = options.fetch(:remote, "flathub")
        url = options[:url]

        # 3-tier remote handling:
        # - Tier 1: Named remote → check with that remote name
        # - Tier 2: URL only → resolve to single-app remote name (<app-id>-origin)
        # - Tier 3: URL + name → check with the named remote
        actual_remote = if url.blank? && remote.start_with?("http://", "https://")
          # Tier 2: URL only - resolve to single-app remote name
          # (.flatpakref - check by name only since remote name varies)
          return self.class.package_installed?(name) if remote.end_with?(".flatpakref")

          self.class.generate_single_app_remote_name(name)
        else
          # Tier 1 (named remote) and Tier 3 (named remote with URL) both use the remote name
          remote
        end

        self.class.package_installed?(name, remote: actual_remote)
      end
    end

    # TODO: Remove these compatibility aliases once bundle callers and tests
    # stop requiring separate flatpak dumper/installer/checker constants.
    FlatpakDumper = Flatpak
    FlatpakInstaller = Flatpak

    module Checker
      # TODO: Remove this compatibility alias once bundle callers and tests stop
      # requiring a separate flatpak checker constant.
      FlatpakChecker = Homebrew::Bundle::Flatpak
    end

    module Commands
      module Cleanup
        class << self
          # TODO: Remove this legacy helper once the direct cleanup specs stop
          # stubbing the old command-level flatpak helper.
          sig { params(global: T::Boolean, file: T.nilable(String)).returns(T::Array[String]) }
          def flatpaks_to_uninstall(global: false, file: nil)
            _ = global
            _ = file
            dsl = Homebrew::Bundle::Commands::Cleanup.dsl
            raise "call `run` or `read_dsl_from_brewfile!` first" if dsl.nil?

            Homebrew::Bundle::Flatpak.cleanup_items(dsl.entries)
          end
        end
      end
    end
  end
end
