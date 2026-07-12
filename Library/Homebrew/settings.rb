# typed: strict
# frozen_string_literal: true

require "cachable"
require "utils/popen"

module Homebrew
  # Helper functions for reading and writing settings.
  module Settings
    extend T::Generic
    extend Cachable

    Cache = type_template { { fixed: T::Hash[Pathname, T::Hash[String, String]] } }

    sig {
      params(setting: T.any(String, Symbol), repo: Pathname)
        .returns(T.nilable(String))
    }
    def self.read(setting, repo: HOMEBREW_REPOSITORY)
      return unless (repo/".git/config").exist?

      value = all(repo)[setting.to_s]

      return if value.nil? || value.strip.empty?

      value
    end

    sig { params(setting: T.any(String, Symbol), value: T.any(String, T::Boolean), repo: Pathname).void }
    def self.write(setting, value, repo: HOMEBREW_REPOSITORY)
      return unless (repo/".git/config").exist?

      value = value.to_s

      return if read(setting, repo:) == value

      Kernel.system("git", "-C", repo.to_s, "config", "--replace-all", "homebrew.#{setting}", value, exception: true)
      cache.delete(repo)
    end

    sig { params(setting: T.any(String, Symbol), repo: Pathname).void }
    def self.delete(setting, repo: HOMEBREW_REPOSITORY)
      return unless (repo/".git/config").exist?

      return if read(setting, repo:).nil?

      Kernel.system("git", "-C", repo.to_s, "config", "--unset-all", "homebrew.#{setting}", exception: true)
      cache.delete(repo)
    end

    # All `homebrew.*` settings in `repo`, cached so that repeated reads cost
    # one `git config` invocation per repository instead of one per setting.
    sig { params(repo: Pathname).returns(T::Hash[String, String]) }
    private_class_method def self.all(repo)
      cache[repo] ||= Utils.popen_read(
        "git", "-C", repo.to_s, "config", "--null", "--get-regexp", "^homebrew\\."
      ).split("\0").to_h do |entry|
        keyvalue = entry.split("\n", 2)
        [keyvalue.fetch(0).delete_prefix("homebrew."), keyvalue.fetch(1, "")]
      end
    end
  end
end
