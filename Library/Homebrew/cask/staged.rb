# typed: true
# frozen_string_literal: true

require "utils/user"

module Cask
  # Helper functions for staged casks.
  module Staged
    # FIXME: Enable cop again when https://github.com/sorbet/sorbet/issues/3532 is fixed.
    # rubocop:disable Style/MutableConstant
    Paths = T.type_alias { T.any(String, Pathname, T::Array[T.any(String, Pathname)]) }
    # rubocop:enable Style/MutableConstant

    sig { params(paths: Paths, permissions_str: String).void }
    def set_permissions(paths, permissions_str)
      full_paths = remove_nonexistent(paths)
      return if full_paths.empty?

      @command.run!("/bin/chmod", args: ["-R", "--", permissions_str, *full_paths],
                                  sudo: false)
    end

    sig { params(paths: Paths, user: T.any(String, User), group: String).void }
    def set_ownership(paths, user: T.must(User.current), group: "staff")
      full_paths = remove_nonexistent(paths)
      return if full_paths.empty?

      ohai "Changing ownership of paths required by #{@cask} with sudo; the password may be necessary."
      @command.run!("/usr/sbin/chown", args: ["-R", "--", "#{user}:#{group}", *full_paths],
                                       sudo: true)
    end

    private

    sig { params(paths: Paths).returns(T::Array[Pathname]) }
    def remove_nonexistent(paths)
      Array(paths).map { |p| Pathname(p).expand_path }.select(&:exist?)
    end
  end
end
