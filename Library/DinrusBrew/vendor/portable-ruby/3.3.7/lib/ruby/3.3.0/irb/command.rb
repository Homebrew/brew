# frozen_string_literal: true
#
#   irb/command.rb - irb command
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require_relative "command/base"

module IRB # :nodoc:
  module Command
    @commands = {}

    class << self
      attr_reader :commands

      # Registers a command with the given name.
      # Aliasing is intentionally not supported at the moment.
      def register(name, command_class)
        @commands[name.to_sym] = [command_class, []]
      end
    end
  end
end
