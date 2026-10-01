# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class Casks < AbstractCommand
      # Used when the Bash implementation falls back to Ruby for tap trust filtering.
      cmd_args do
        description "List all locally installable casks including short names."
      end

      sig { override.void }
      def run
        require "cask/cask"

        puts Cask::Cask.all.flat_map { |cask| [cask.full_name, cask.token] }.uniq.sort
      end
    end
  end
end
