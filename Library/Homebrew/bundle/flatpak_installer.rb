# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module FlatpakInstaller
      sig { void }
      def self.reset!
        @installed_packages = nil
      end

      sig {
        params(
          name:     String,
          verbose:  T::Boolean,
          remote:   String,
          url:      T.nilable(String),
          _options: T.anything,
        ).returns(T::Boolean)
      }
      def self.preinstall!(name, verbose: false, remote: "flathub", url: nil, **_options)
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
          preinstall: T::Boolean,
          verbose:    T::Boolean,
          force:      T::Boolean,
          remote:     String,
          url:        T.nilable(String),
          _options:   T.anything,
        ).returns(T::Boolean)
      }
      def self.install!(name, preinstall: true, verbose: false, force: false, remote: "flathub", url: nil, **_options)
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
        return false unless Bundle.system flatpak, "install", "-y", "--system", actual_remote, name,
                                          verbose: verbose

        installed_packages << { name:, remote: actual_remote }
        true
      end

      # Install from a .flatpakref file (Tier 2 variant - Flatpak handles single-app remote natively)
      sig { params(flatpak: String, name: String, url: String, verbose: T::Boolean).returns(T::Boolean) }
      def self.install_flatpakref!(flatpak, name, url, verbose:)
        return false unless Bundle.system flatpak, "install", "-y", "--system", url,
                                          verbose: verbose

        # Get the actual remote name used by Flatpak
        output = `#{flatpak} list --app --columns=application,origin 2>/dev/null`.chomp
        installed = output.split("\n").find { |line| line.start_with?(name) }
        actual_remote = installed ? installed.split("\t")[1] : "#{name}-origin"
        installed_packages << { name:, remote: actual_remote }
        true
      end

      # Generate a single-app remote name (Tier 2)
      # Pattern: <app-id>-origin (matches Flatpak's native behavior for .flatpakref)
      sig { params(app_id: String).returns(String) }
      def self.generate_single_app_remote_name(app_id)
        "#{app_id}-origin"
      end

      # Ensure a single-app remote exists (Tier 2)
      # Safe to replace if URL differs since it's isolated per-app
      sig { params(flatpak: String, remote_name: String, url: String, verbose: T::Boolean).void }
      def self.ensure_single_app_remote_exists!(flatpak, remote_name, url, verbose:)
        existing_url = get_remote_url(flatpak, remote_name)

        if existing_url && existing_url != url
          # Single-app remote with different URL - safe to replace
          puts "Replacing single-app remote #{remote_name} (URL changed)" if verbose
          Bundle.system flatpak, "remote-delete", "--system", "--force", remote_name, verbose: verbose
          existing_url = nil
        end

        return if existing_url # Already exists with correct URL

        puts "Adding single-app remote #{remote_name} from #{url}" if verbose
        add_remote!(flatpak, remote_name, url, verbose:)
      end

      # Ensure a named shared remote exists (Tier 3)
      # Warn but don't change if URL differs (user explicitly named it)
      sig { params(flatpak: String, remote_name: String, url: String, verbose: T::Boolean).void }
      def self.ensure_named_remote_exists!(flatpak, remote_name, url, verbose:)
        existing_url = get_remote_url(flatpak, remote_name)

        if existing_url && existing_url != url
          # Named remote with different URL - warn but don't change (user explicitly named it)
          puts "Warning: Remote '#{remote_name}' exists with different URL (#{existing_url}), using existing"
          return
        end

        return if existing_url # Already exists with correct URL

        puts "Adding named remote #{remote_name} from #{url}" if verbose
        add_remote!(flatpak, remote_name, url, verbose:)
      end

      # Get URL for an existing remote, or nil if not found
      sig { params(flatpak: String, remote_name: String).returns(T.nilable(String)) }
      def self.get_remote_url(flatpak, remote_name)
        output = `#{flatpak} remote-list --system --columns=name,url 2>/dev/null`.chomp
        output.split("\n").each do |line|
          parts = line.split("\t")
          return parts[1] if parts[0] == remote_name
        end
        nil
      end

      # Add a remote with appropriate flags
      sig { params(flatpak: String, remote_name: String, url: String, verbose: T::Boolean).returns(T::Boolean) }
      def self.add_remote!(flatpak, remote_name, url, verbose:)
        if url.end_with?(".flatpakrepo")
          Bundle.system flatpak, "remote-add", "--if-not-exists", "--system",
                        remote_name, url, verbose: verbose
        else
          # For bare repository URLs, add with --no-gpg-verify for user repos
          Bundle.system flatpak, "remote-add", "--if-not-exists", "--system",
                        "--no-gpg-verify", remote_name, url, verbose: verbose
        end
      end

      sig { params(package: String, remote: T.nilable(String)).returns(T::Boolean) }
      def self.package_installed?(package, remote: nil)
        if remote
          # Check if package is installed from the specified remote
          installed_packages.any? { |pkg| pkg[:name] == package && pkg[:remote] == remote }
        else
          # Just check if package is installed from any remote
          installed_packages.any? { |pkg| pkg[:name] == package }
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def self.installed_packages
        require "bundle/flatpak_dumper"
        @installed_packages ||= T.let(
          Homebrew::Bundle::FlatpakDumper.packages_with_remotes,
          T.nilable(T::Array[T::Hash[Symbol, String]]),
        )
      end
    end
  end
end
