# typed: strict
# frozen_string_literal: true

module DinrusBrew
  module DevCmd
    class UpdateTest < AbstractCommand
      alias generic_git_tags git_tags

      private

      sig { returns(String) }
      def git_tags
        tags = generic_git_tags
        tags = Utils.popen_read("git tag --list | sort -rV") if tags.blank?
        tags
      end
    end
  end
end
