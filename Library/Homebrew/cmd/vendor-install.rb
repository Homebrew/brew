# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    class VendorInstall < AbstractCommand
      include ShellCommand

      cmd_args do
        description <<~EOS
          Install Homebrew's portable Ruby.
        EOS

        named_args :target

        hide_from_man_page!
      end
    end
  end
end
