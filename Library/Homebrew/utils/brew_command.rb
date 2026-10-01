# typed: strict
# frozen_string_literal: true

require "system_command"

module Utils
  module BrewCommand
    module_function

    sig { params(args: T.any(String, Pathname)).void }
    def run!(*args)
      SystemCommand.safe_system(HOMEBREW_BREW_FILE, *args)
    end
  end
end
