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
    private_class_method :token_from_full_token

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

    sig { returns(String) }
    def self.expected_caskroom_group
      "admin"
    end

    # Get all installed casks.
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
      end.select(&:installed?)
    end
  end
end

require "extend/os/cask/caskroom"
