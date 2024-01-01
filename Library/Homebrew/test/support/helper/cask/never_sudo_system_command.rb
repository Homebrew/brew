# typed: true
# frozen_string_literal: true

require "system_command"

class NeverSudoSystemCommand < SystemCommand
  def self.run(command, **options)
    super(command, **options.merge(sudo: false, sudo_as_root: false))
  end
end
