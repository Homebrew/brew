# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"

module Cask
  module Artifact
    # Artifact corresponding to the `flatpak` stanza.
    #
    # Installs a Flatpak application from a remote repository.
    # Linux-only artifact.
    class Flatpak < AbstractArtifact
      attr_reader :app_id, :stanza_options

      def self.from_args(cask, app_id, **stanza_options)
        stanza_options.assert_valid_keys(:remote, :url)
        new(cask, app_id, **stanza_options)
      end

      def initialize(cask, app_id, **stanza_options)
        super(cask)
        @app_id = app_id
        @stanza_options = stanza_options
      end

      def summarize
        app_id
      end

      def install_phase(command: nil, verbose: false, **_options)
        ensure_flatpak_installed(command:, verbose:)

        if app_installed?
          ohai "Flatpak '#{app_id}' is already installed from '#{remote}'" if verbose
          return
        end

        install_flatpak_app(command:, verbose:)
      end

      def uninstall_phase(command: nil, verbose: false, **_options)
        return unless app_installed?

        ohai "Uninstalling Flatpak '#{app_id}'"

        command.run!(
          flatpak_command,
          args:         ["uninstall", "-y", "--system", app_id],
          print_stdout: verbose,
        )
      end

      private

      def remote
        @remote ||= stanza_options.fetch(:remote, "flathub")
      end

      def remote_url
        @remote_url ||= stanza_options[:url]
      end

      def flatpak_command
        @flatpak_command ||= which("flatpak")
      end

      def flatpak_installed?
        !flatpak_command.nil?
      end

      def app_installed?
        return false unless flatpak_installed?

        output = Utils.safe_popen_read(flatpak_command, "list", "--app", "--columns=application,origin")
        output.lines.any? do |line|
          parts = line.strip.split("\t")
          parts[0] == app_id && (parts[1].blank? || parts[1] == remote)
        end
      rescue
        false
      end

      def ensure_flatpak_installed(command:, verbose:)
        return if flatpak_installed?

        ohai "Installing flatpak package manager..."

        # Use Homebrew to install flatpak formula
        system(HOMEBREW_BREW_FILE, "install", "--formula", "flatpak", *("--verbose" if verbose))

        # Reset cache
        @flatpak_command = nil

        return if flatpak_installed?

        raise CaskError, "Failed to install flatpak. Cannot install '#{app_id}'."
      end

      def ensure_remote_exists(verbose:)
        return if remote_exists?

        if remote == "flathub"
          # Auto-add flathub with default URL
          ohai "Adding flathub remote (default Flatpak repository)..."
          system(
            flatpak_command.to_s,
            "remote-add",
            "--if-not-exists",
            "--system",
            "flathub",
            "https://flathub.org/repo/flathub.flatpakrepo",
          )

          raise CaskError, "Failed to add flathub remote. Cannot install '#{app_id}'." unless remote_exists?
        elsif remote_url
          # Auto-add custom remote with provided URL
          ohai "Adding '#{remote}' remote..."
          system(
            flatpak_command.to_s,
            "remote-add",
            "--if-not-exists",
            "--system",
            remote,
            remote_url,
          )

          raise CaskError, "Failed to add '#{remote}' remote. Cannot install '#{app_id}'." unless remote_exists?
        else
          # Custom remote without URL - require manual setup
          raise CaskError, <<~EOS
            Flatpak remote '#{remote}' is not configured.
            Please add it first with:
              flatpak remote-add --system #{remote} <url>

            Or add the url: parameter to the cask:
              flatpak "#{app_id}", remote: "#{remote}", url: "https://..."
          EOS
        end
      end

      def remote_exists?
        return false unless flatpak_installed?

        output = Utils.safe_popen_read(flatpak_command, "remote-list", "--system", "--columns=name")
        output.lines.map(&:strip).include?(remote)
      rescue
        false
      end

      def install_flatpak_app(command:, verbose:)
        ensure_remote_exists(verbose:)

        ohai "Installing Flatpak '#{app_id}' from '#{remote}'"

        command.run!(
          flatpak_command,
          args:         ["install", "-y", "--system", remote, app_id],
          print_stdout: verbose,
        )
      end
    end
  end
end
