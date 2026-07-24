# typed: strict
# frozen_string_literal: true

require "utils/user"
require "utils/output"

module Cask
  # Helper functions for interacting with the `Caskroom` directory.
  #
  # @api internal
  module Caskroom
    extend ::Utils::Output::Mixin

    CASKFILE_EXTENSIONS = %w[json internal.json rb].freeze

    sig { returns(Pathname) }
    def self.path
      @path ||= T.let(HOMEBREW_PREFIX/"Caskroom", T.nilable(Pathname))
    end

    # Return all paths for installed casks.
    sig { returns(T::Array[Pathname]) }
    def self.paths
      return [] unless path.exist?

      path.children.select { |p| p.directory? && !p.symlink? }
    end
    private_class_method :paths

    # Return all tokens for installed casks.
    sig { returns(T::Array[String]) }
    def self.tokens
      paths.map { |path| path.basename.to_s }
    end

    sig { returns(T::Boolean) }
    def self.any_casks_installed?
      paths.any?
    end

    sig { params(token: String).returns(T::Boolean) }
    def self.cask_installed?(token)
      !cask_installed_version(token).nil?
    end

    sig { params(token: String, old_tokens: T::Array[String]).returns(T.nilable(Pathname)) }
    def self.cask_installed_caskfile(token, old_tokens: [])
      # Check if the cask is installed with an old name.
      [token, *old_tokens].map { |cask_token| token_from_full_token(cask_token) }.uniq.each do |cask_token|
        caskroom_path = path/cask_token
        next if !caskroom_path.directory? || caskroom_path.symlink?

        timestamped_path = Pathname.glob((caskroom_path/".metadata/*/*").to_s).max_by { |p| p.basename.to_s }
        next unless timestamped_path

        caskfile = CASKFILE_EXTENSIONS.map { |ext| timestamped_path/"Casks/#{cask_token}.#{ext}" }
                                      .find(&:exist?)
        return caskfile if caskfile
      end

      nil
    end

    sig { params(token: String, old_tokens: T::Array[String]).returns(T.nilable(String)) }
    def self.cask_installed_version(token, old_tokens: [])
      return unless (caskfile = cask_installed_caskfile(token, old_tokens:))

      caskfile.dirname.dirname.dirname.basename.to_s
    end

    sig { params(caskfile: Pathname).void }
    def self.migrate_caskfile_to_json(caskfile)
      # Parse regular installed JSON so current files can be skipped and useful URL data can survive repairs.
      token = CaskLoader.token_from_path(caskfile)
      installed_json_caskfile = CaskLoader.installed_json_caskfile?(caskfile)
      source_json = CaskLoader.load_installed_json(caskfile)

      source_artifacts = nil
      source_url_specs = nil
      current_json = false
      if source_json
        raw_source_artifacts = source_json["artifacts"]
        raw_source_version = source_json["version"]
        raw_source_url_specs = source_json["url_specs"]
        source_artifacts = raw_source_artifacts if raw_source_artifacts.is_a?(Array)
        source_url_specs = raw_source_url_specs if raw_source_url_specs.is_a?(Hash)

        # Installed JSON only supplements metadata available from the path or receipt: artifacts and version preserve
        # otherwise-lost installed values, while url_specs preserves an artifact's staged source path.
        current_json = (source_json.keys - %w[artifacts url_specs version]).empty? &&
                       (raw_source_artifacts.nil? || !source_artifacts.nil?) &&
                       (raw_source_version.nil? || raw_source_version.is_a?(String)) &&
                       (raw_source_url_specs.nil? || !source_url_specs.nil?)
      end

      # Recover missing receipt and legacy caskfile data before deciding what must be stored in the JSON.
      tab = CaskLoader.load_installed_tab(token)

      cask = begin
        if installed_json_caskfile
          CaskLoader.load_from_installed_caskfile(caskfile)
        else
          CaskLoader.load(caskfile, warn: false)
        end
      rescue CaskInvalidError, CaskUnavailableError, MethodDeprecatedError, JSON::ParserError, NoMethodError,
             TypeError
        nil
      end
      return if current_json && cask && (!source_artifacts.nil? || tab.uninstall_artifacts.present?)
      return if cask&.uninstall_flight_blocks? || tab.uninstall_flight_blocks

      cask ||= CaskLoader.recover_from_installed_caskfile(caskfile, tab:)
      return unless cask

      # Preserve the original version and artifacts whenever the receipt cannot reproduce them.
      version = cask.version.to_s
      json_uninstall_artifacts = JSON.parse(JSON.generate(cask.artifacts_list(uninstall_only: true)))
      # Keep missing artifacts distinguishable from an intentional empty artifact list.
      return if source_artifacts.nil? && tab.uninstall_artifacts.blank? && json_uninstall_artifacts.empty?

      installed_json = cask.to_installed_json_hash
      installed_json["url_specs"] ||= source_url_specs if source_url_specs
      receipt_artifacts = tab.uninstall_artifacts.presence
      if receipt_artifacts.nil? || !artifacts_equivalent?(receipt_artifacts, json_uninstall_artifacts)
        installed_json["artifacts"] = json_uninstall_artifacts
      end
      installed_json["version"] = version if caskfile.dirname.dirname.dirname.basename.to_s != version

      # Replace the old metadata only after the new JSON reloads with the selected version and artifacts.
      json_caskfile = caskfile.dirname/"#{token}.json"
      original_contents = caskfile.read if caskfile == json_caskfile
      json_caskfile.atomic_write(JSON.pretty_generate(installed_json))
      begin
        # Only durable on-disk data may satisfy this check: the API fallback would mask a
        # migrated caskfile that lost its artifacts for as long as the API definition matches.
        migrated_cask = CaskLoader.load_from_installed_caskfile(json_caskfile, api_fallback: false)
        migrated_artifacts = JSON.parse(JSON.generate(migrated_cask.artifacts_list(uninstall_only: true)))
        if migrated_cask.version.to_s != version ||
           !artifacts_equivalent?(migrated_artifacts, json_uninstall_artifacts)
          raise "migrated Cask metadata differs from the original after preserving version and artifacts"
        end
      rescue
        if original_contents
          json_caskfile.atomic_write(original_contents)
        elsif json_caskfile.exist?
          json_caskfile.unlink
        end
        raise
      end
      caskfile.unlink if caskfile != json_caskfile
    end

    sig { params(first: T::Array[T.anything], second: T::Array[T.anything]).returns(T::Boolean) }
    def self.artifacts_equivalent?(first, second)
      first.tally == second.tally
    end
    private_class_method :artifacts_equivalent?

    # Return tokens for Caskroom directories missing expected installed metadata.
    sig { returns(T::Array[String]) }
    def self.corrupt_cask_dirs
      paths.filter_map { |p| p.basename.to_s unless cask_with_metadata?(p) }
    end

    sig { params(cask_path: Pathname).returns(T::Boolean) }
    def self.cask_with_metadata?(cask_path)
      cask_path.glob(".metadata/*/*/Casks/*.{rb,json}").any?
    end
    private_class_method :cask_with_metadata?

    sig { params(token: String).returns(String) }
    def self.token_from_full_token(token)
      _, _, cask_token = token.split("/", 3)
      cask_token || token
    end

    sig { void }
    def self.ensure_caskroom_exists
      return if path.exist?

      sudo = !path.parent.writable?

      if sudo && !ENV.key?("SUDO_ASKPASS") && $stdout.tty?
        ohai "Creating Caskroom directory: #{path}",
             "We'll set permissions properly so we won't need sudo in the future."
      end

      SystemCommand.run("mkdir", args: ["-p", path], sudo:)
      SystemCommand.run("chmod", args: ["g+rwx", path], sudo:)
      SystemCommand.run("chown", args: [User.current.to_s, path], sudo:)

      chgrp_path(path, sudo) unless caskroom_group_correct?(path)
    end

    sig { params(path: Pathname, sudo: T::Boolean).void }
    def self.chgrp_path(path, sudo)
      SystemCommand.run("chgrp", args: [expected_caskroom_group, path], sudo:)
    end

    sig { params(path: Pathname).returns(T::Boolean) }
    def self.caskroom_group_correct?(path)
      group = Etc.getgrnam(expected_caskroom_group)
      return false if group.nil?

      path.stat.gid == group.gid
    end

    @expected_caskroom_group = T.let(nil, T.nilable(String))

    class << self
      sig { params(expected_caskroom_group: T.nilable(String)).void }
      attr_writer :expected_caskroom_group
    end

    sig { returns(String) }
    def self.expected_caskroom_group
      "admin"
    end

    # Get all installed casks.
    #
    # A Caskroom directory for a cask that has been renamed but not yet migrated loads
    # as the cask it was renamed to, so deduplicate to avoid listing it twice.
    #
    # @api internal
    sig { params(config: T.nilable(Config)).returns(T::Array[Cask]) }
    def self.casks(config: nil)
      tokens.sort.filter_map do |token|
        # This is nested so that the rescue can catch errors from both branches
        begin
          CaskLoader.load_prefer_installed(token, config:, warn: false)
        rescue TapCaskAmbiguityError => e
          e.loaders.fetch(0).load(config:)
        end
      rescue Homebrew::UntrustedTapError
        # If the tap is untrusted the only place we can load the cask from is the installed cask file, if it exists.
        begin
          CaskLoader::FromInstalledPathLoader.try_new(token, warn: false)&.load(config:)
        rescue
          nil
        end
      rescue
        # Don't blow up because of a single unavailable cask.
        nil
      end.select(&:installed?).uniq(&:full_name)
    end
  end
end

require "extend/os/cask/caskroom"
