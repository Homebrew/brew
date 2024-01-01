# typed: strict
# frozen_string_literal: true

module Homebrew
  class << self
    alias generic_git_tags git_tags

    sig { returns(String) }
    def git_tags
      tags = generic_git_tags
      tags = Utils.popen_read("git tag --list | sort -rV") if tags.blank?
      tags
    end
  end
end
