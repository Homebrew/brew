# typed: strict
# frozen_string_literal: true

require "utils/user"

module Cask
  # Helper functions for interacting with the `Caskroom` directory.
  #
  # @api internal
  module Caskroom
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

    sig { void }
    def self.ensure_caskroom_exists
      return if path.exist?

      sudo = !path.parent.writable?

      if sudo && !ENV.key?("SUDO_ASKPASS") && $stdout.tty?
        ohai "Creating Caskroom directory: #{path}",
             "We'll set permissions properly so we won't need sudo in the future."
      end

      SystemCommand.run("/bin/mkdir", args: ["-p", path], sudo:)
      SystemCommand.run("/bin/chmod", args: ["g+rwx", path], sudo:)
      SystemCommand.run("/usr/sbin/chown", args: [User.current, path], sudo:)
      SystemCommand.run("/usr/bin/chgrp", args: ["admin", path], sudo:)
    end

    # Get all installed casks.
    #
    # @api internal
    sig { params(config: T.nilable(Config)).returns(T::Array[Cask]) }
    def self.casks(config: nil)
      tokens.sort.filter_map do |token|
        CaskLoader.load_prefer_installed(token, config:, warn: false)
      rescue TapCaskAmbiguityError => e
        T.must(e.loaders.first).load(config:)
      rescue
        # Don't blow up because of a single unavailable cask.
        nil
      end
    end
  end
end
