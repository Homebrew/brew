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

      SystemCommand.run("mkdir", args: ["-p", path], sudo:)
      SystemCommand.run("chmod", args: ["g+rwx", path], sudo:)
      SystemCommand.run("chown", args: [User.current.to_s, path], sudo:)

      chgrp_path(path, sudo)
    end

    sig { params(path: Pathname, sudo: T::Boolean).void }
    def self.chgrp_path(path, sudo)
      SystemCommand.run("chgrp", args: ["admin", path], sudo:)
    end

    # Get all installed casks.
    #
    # @api internal
    sig { params(config: T.nilable(Config)).returns(T::Array[Cask]) }
    def self.casks(config: nil)
      tokens.sort.filter_map do |token|
        CaskLoader.load_prefer_installed(token, config:, warn: false)
      rescue TapCaskAmbiguityError => e
        e.loaders.fetch(0).load(config:)
      rescue
        # Don't blow up because of a single unavailable cask.
        nil
      end
    end
  end
end

require "extend/os/cask/caskroom"
