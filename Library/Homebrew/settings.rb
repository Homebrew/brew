# typed: true
# frozen_string_literal: true

require "utils/popen"

module Homebrew
  # Helper functions for reading and writing settings.
  #
  # @api private
  module Settings
    def self.read(setting, repo: HOMEBREW_REPOSITORY)
      return unless (repo/".git/config").exist?

      value = Utils.popen_read("git", "-C", repo.to_s, "config", "--get", "homebrew.#{setting}").chomp

      return if value.strip.empty?

      value
    end

    def self.write(setting, value, repo: HOMEBREW_REPOSITORY)
      return unless (repo/".git/config").exist?

      value = value.to_s

      return if read(setting, repo: repo) == value

      Kernel.system("git", "-C", repo.to_s, "config", "--replace-all", "homebrew.#{setting}", value, exception: true)
    end

    def self.delete(setting, repo: HOMEBREW_REPOSITORY)
      return unless (repo/".git/config").exist?

      return if read(setting, repo: repo).nil?

      Kernel.system("git", "-C", repo.to_s, "config", "--unset-all", "homebrew.#{setting}", exception: true)
    end
  end
end
