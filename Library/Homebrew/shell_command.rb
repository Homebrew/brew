# typed: strict
# frozen_string_literal: true

module Homebrew
  module ShellCommand
    extend T::Helpers

    requires_ancestor { AbstractCommand }

    sig { void }
    def run
      T.bind(self, AbstractCommand)

      sh_cmd_path = "#{self.class.dev_cmd? ? "dev-cmd" : "cmd"}/#{self.class.command_name}.sh"
      raise StandardError,
            "This command is just here for completions generation. " \
            "It's actually defined in `#{sh_cmd_path}` instead."
    end
  end
end
