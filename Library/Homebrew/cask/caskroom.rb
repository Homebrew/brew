# typed: true
# frozen_string_literal: true

require "utils/user"

module Cask
  # Helper functions for interacting with the `Caskroom` directory.
  #
  # @api private
  module Caskroom
    sig { returns(Pathname) }
    def self.path
      @path ||= HOMEBREW_PREFIX/"Caskroom"
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

      SystemCommand.run("/bin/mkdir", args: ["-p", path], sudo: sudo)
      SystemCommand.run("/bin/chmod", args: ["g+rwx", path], sudo: sudo)
      SystemCommand.run("/usr/sbin/chown", args: [User.current, path], sudo: sudo)
      SystemCommand.run("/usr/bin/chgrp", args: ["admin", path], sudo: sudo)
    end

    sig { params(config: T.nilable(Config)).returns(T::Array[Cask]) }
    def self.casks(config: nil)
      tokens.sort.map do |token|
        CaskLoader.load(token, config: config)
      rescue TapCaskAmbiguityError
        tap_path = CaskLoader.tap_paths(token).first
        CaskLoader::FromTapPathLoader.new(tap_path).load(config: config)
      rescue
        # Don't blow up because of a single unavailable cask.
        nil
      end.compact
    end
  end
end
