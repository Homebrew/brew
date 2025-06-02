# frozen_string_literal: true

module IRB
  class Statement
    attr_reader :code

    def is_assignment?
      raise NotImplementedError
    end

    def suppresses_echo?
      raise NotImplementedError
    end

    def should_be_handled_by_debugger?
      raise NotImplementedError
    end

    class EmptyInput < Statement
      def is_assignment?
        false
      end

      def suppresses_echo?
        true
      end

      # Debugger takes empty input to repeat the last command
      def should_be_handled_by_debugger?
        true
      end

      def code
        ""
      end
    end

    class Expression < Statement
      def initialize(code, is_assignment)
        @code = code
        @is_assignment = is_assignment
      end

      def suppresses_echo?
        @code.match?(/;\s*\z/)
      end

      def should_be_handled_by_debugger?
        true
      end

      def is_assignment?
        @is_assignment
      end
    end

    class Command < Statement
      attr_reader :command_class, :arg

      def initialize(original_code, command_class, arg)
        @code = original_code
        @command_class = command_class
        @arg = arg
      end

      def is_assignment?
        false
      end

      def suppresses_echo?
        false
      end

      def should_be_handled_by_debugger?
        require_relative 'command/debug'
        IRB::Command::DebugCommand > @command_class
      end
    end
  end
end
