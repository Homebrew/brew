# typed: strict
# frozen_string_literal: true

module Homebrew
  module ShellCommand
    extend T::Helpers

    requires_ancestor { AbstractCommand }

    sig { void }
    def run
      T.bind(self, AbstractCommand)

      command_dir = self.class.dev_cmd? ? "dev-cmd" : "cmd"
      sh_cmd_path = "#{command_dir}/#{self.class.command_name}.sh"
      raise StandardError,
            "This command is just here for completions generation. " \
            "It's actually defined in `#{sh_cmd_path}` instead."
    end
  end
end
