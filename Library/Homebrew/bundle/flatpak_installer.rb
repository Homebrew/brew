# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module FlatpakInstaller
      def self.reset!
        @installed_packages = nil
      end

      def self.preinstall!(name, verbose: false, remote: "flathub", **_options)
        return false unless Bundle.flatpak_installed?

        # Check if package is installed at all (regardless of remote)
        if package_installed?(name)
          puts "Skipping install of #{name} Flatpak. It is already installed." if verbose
          return false
        end

        true
      end

      def self.install!(name, preinstall: true, verbose: false, force: false, remote: "flathub", **_options)
        return true unless Bundle.flatpak_installed?
        return true unless preinstall

        puts "Installing #{name} Flatpak from #{remote}. It is not currently installed." if verbose

        flatpak = Bundle.which_flatpak

        # Handle remote URLs vs remote names
        if remote.start_with?("http://", "https://")
          # Check if it's a .flatpakref file (can install directly)
          if remote.end_with?(".flatpakref")
            # For .flatpakref files, install directly
            return false unless Bundle.system flatpak.to_s, "install", "-y", "--system", remote,
                                              verbose: verbose

            # Get the actual remote name used
            output = `#{flatpak} list --app --columns=application,origin 2>/dev/null`.chomp
            installed = output.split("\n").find { |line| line.start_with?(name) }
            actual_remote = installed ? installed.split("\t")[1] : remote
            installed_packages << { name:, remote: actual_remote || remote }
          else
            # For repository URLs (.flatpakrepo or bare URLs), we need to add the remote first
            # Generate a remote name from the URL
            remote_name = generate_remote_name(remote)

            # Check if remote already exists and get its URL
            existing_remotes = `#{flatpak} remote-list --system --columns=name,url 2>/dev/null`.chomp
            existing_remote_url = T.let(nil, T.nilable(String))
            existing_remotes.split("\n").each do |line|
              parts = line.split("\t")
              if parts[0] == remote_name
                existing_remote_url = parts[1]
                break
              end
            end

            if existing_remote_url && existing_remote_url != remote
              # Remote exists but points to different URL - remove old remote and package
              puts "Remote #{remote_name} exists with different URL. Removing old remote and package." if verbose

              # Uninstall the package if it's installed
              if package_installed?(name)
                puts "Uninstalling #{name} from old remote" if verbose
                Bundle.system flatpak.to_s, "uninstall", "-y", "--system", name, verbose: verbose
              end

              # Remove the old remote
              puts "Removing old remote #{remote_name}" if verbose
              Bundle.system flatpak.to_s, "remote-delete", "--system", remote_name, verbose: verbose

              existing_remote_url = nil # Mark as non-existent so we add the new one
            end

            unless existing_remote_url
              puts "Adding flatpak remote #{remote_name} from #{remote}" if verbose
              # Try adding as .flatpakrepo first, fall back to bare URL
              if remote.end_with?(".flatpakrepo")
                return false unless Bundle.system flatpak.to_s, "remote-add", "--if-not-exists", "--system",
                                                  remote_name, remote, verbose: verbose
              else
                # For bare repository URLs, add with --no-gpg-verify for user repos
                return false unless Bundle.system flatpak.to_s, "remote-add", "--if-not-exists", "--system",
                                                  "--no-gpg-verify", remote_name, remote, verbose: verbose
              end
            end

            # Install from the remote
            return false unless Bundle.system flatpak.to_s, "install", "-y", "--system", remote_name, name,
                                              verbose: verbose

            installed_packages << { name:, remote: remote_name }
          end
        else
          # Treat as a remote name (like "flathub")
          return false unless Bundle.system flatpak.to_s, "install", "-y", "--system", remote, name,
                                            verbose: verbose

          installed_packages << { name:, remote: }
        end

        true
      end

      # Generate a deterministic remote name from a URL
      def self.generate_remote_name(url)
        require "uri"

        # Try to extract a meaningful name from the URL
        uri = URI.parse(url)

        # Extract hostname parts (e.g., "dl.flathub.org" -> "flathub")
        host_parts = uri.host&.split(".")&.reject { |p| ["www", "dl"].include?(p) } || []
        base_name = host_parts.first || "remote"

        # Add path hint if available (e.g., "/beta-repo/" -> "beta")
        # Get first non-empty path segment, split on hyphens, and filter out "repo"/"flatpak"
        path_segments = uri.path&.split("/")&.reject(&:empty?)
        if path_segments&.any?
          path_segment = T.must(path_segments.first)
          # Split on hyphens and underscores, filter out common terms
          path_parts = path_segment.split(/[-_]/).grep_v(/^(repo|flatpak)s?$/i)
          path_hint = path_parts.join("-") unless path_parts.empty?
          base_name = "#{base_name}-#{path_hint}" if path_hint.present?
        end

        # Clean up the name to be flatpak-friendly (lowercase, alphanumeric + hyphens)
        base_name.downcase.gsub(/[^a-z0-9-]/, "")
      end

      def self.package_installed?(package, remote: nil)
        if remote
          # Check if package is installed from the specified remote
          installed_packages.any? { |pkg| pkg[:name] == package && pkg[:remote] == remote }
        else
          # Just check if package is installed from any remote
          installed_packages.any? { |pkg| pkg[:name] == package }
        end
      end

      def self.installed_packages
        require "bundle/flatpak_dumper"
        @installed_packages ||= Homebrew::Bundle::FlatpakDumper.packages_with_remotes
      end
    end
  end
end

require "extend/os/bundle/flatpak_installer"
