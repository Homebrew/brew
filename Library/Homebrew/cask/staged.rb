# typed: strict
# frozen_string_literal: true

require "cask/quarantine"
require "utils/user"
require "utils/output"

module Cask
  # Helper functions for staged casks.
  module Staged
    include ::Utils::Output::Mixin
    extend T::Helpers

    requires_ancestor { ::Cask::DSL::Base }

    Paths = T.type_alias { T.any(String, Pathname, T::Array[T.any(String, Pathname)]) }

    sig { params(paths: Paths, permissions_str: String).void }
    def set_permissions(paths, permissions_str)
      full_paths = remove_nonexistent(paths)
      return if full_paths.empty?

      command.run!("chmod", args: ["-R", "--", permissions_str, *full_paths],
                            sudo: false)
    end

    sig { params(paths: Paths, user: T.any(String, User), group: String).void }
    def set_ownership(paths, user: T.must(User.current), group: "staff")
      full_paths = remove_nonexistent(paths)
      return if full_paths.empty?

      # On macOS Ventura or later, modifying the contents of an app bundle
      # requires App Management permissions, even when using `sudo`. Without
      # them, every `chown` fails with `Operation not permitted`, so check
      # upfront: this triggers the system permission prompt (which a plain
      # `chown` does not) and allows giving the user an actionable error
      # message instead of a wall of `chown` errors.
      full_paths.each do |path|
        next if Quarantine.app_management_permissions_granted?(app: path, command:)

        raise CaskError, <<~EOS
          Cannot change the ownership of '#{path}' because your terminal does not have App Management permissions.
          macOS prevents modifying apps without these permissions, even when using `sudo`.
          To fix this, approve the permissions prompt (if one was just shown) or go to
          System Settings → Privacy & Security → App Management and add or enable your terminal.
          Then run this command again.
        EOS
      end

      ohai "Changing ownership of paths required by #{cask} with `sudo` (which may request your password)..."
      command.run!("chown", args: ["-R", "--", "#{user}:#{group}", *full_paths],
                            sudo: true)
    end

    private

    sig { params(paths: Paths).returns(T::Array[Pathname]) }
    def remove_nonexistent(paths)
      Array(paths).map { |p| Pathname(p).expand_path }.select(&:exist?)
    end
  end
end
