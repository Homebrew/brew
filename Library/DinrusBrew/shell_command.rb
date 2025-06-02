# typed: strict
# frozen_string_literal: true

module DinrusBrew
  module ShellCommand
    extend T::Helpers

    requires_ancestor { AbstractCommand }

    sig { void }
    def run
      T.bind(self, AbstractCommand)

      sh_cmd_path = "#{self.class.dev_cmd? ? "dev-cmd" : "cmd"}/#{self.class.command_name}.sh"
      raise StandardError,
            "Эта команда здесь только для генерации комплеций. " \
            "На самом деле она определена в `#{sh_cmd_path}."
    end
  end
end
