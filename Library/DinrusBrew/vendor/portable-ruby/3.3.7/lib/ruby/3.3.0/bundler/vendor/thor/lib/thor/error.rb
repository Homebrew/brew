class Bundler::Thor
  Correctable = if defined?(DidYouMean::SpellChecker) && defined?(DidYouMean::Correctable) # rubocop:disable Naming/ConstantName
    Module.new do
      def to_s
        super + DidYouMean.formatter.message_for(corrections)
      end

      def corrections
        @corrections ||= self.class.const_get(:SpellChecker).new(self).corrections
      end
    end
  end

  # Bundler::Thor::Error is raised when it's caused by wrong usage of thor classes. Those
  # errors have their backtrace suppressed and are nicely shown to the user.
  #
  # Errors that are caused by the developer, like declaring a method which
  # overwrites a thor keyword, SHOULD NOT raise a Bundler::Thor::Error. This way, we
  # ensure that developer errors are shown with full backtrace.
  class Error < StandardError
  end

  # Raised when a command was not found.
  class UndefinedCommandError < Error
    class SpellChecker
      attr_reader :error

      def initialize(error)
        @error = error
      end

      def corrections
        @corrections ||= spell_checker.correct(error.command).map(&:inspect)
      end

      def spell_checker
        DidYouMean::SpellChecker.new(dictionary: error.all_commands)
      end
    end

    attr_reader :command, :all_commands

    def initialize(command, all_commands, namespace)
      @command = command
      @all_commands = all_commands

      message = "Could not find command #{command.inspect}"
      message = namespace ? "#{message} in #{namespace.inspect} namespace." : "#{message}."

      super(message)
    end

    prepend Correctable if Correctable
  end
  UndefinedTaskError = UndefinedCommandError

  class AmbiguousCommandError < Error
  end
  AmbiguousTaskError = AmbiguousCommandError

  # Raised when a command was found, but not invoked properly.
  class InvocationError < Error
  end

  class UnknownArgumentError < Error
    class SpellChecker
      attr_reader :error

      def initialize(error)
        @error = error
      end

      def corrections
        @corrections ||=
          error.unknown.flat_map { |unknown| spell_checker.correct(unknown) }.uniq.map(&:inspect)
      end

      def spell_checker
        @spell_checker ||= DidYouMean::SpellChecker.new(dictionary: error.switches)
      end
    end

    attr_reader :switches, :unknown

    def initialize(switches, unknown)
      @switches = switches
      @unknown = unknown

      super("Unknown switches #{unknown.map(&:inspect).join(', ')}")
    end

    prepend Correctable if Correctable
  end

  class RequiredArgumentMissingError < InvocationError
  end

  class MalformattedArgumentError < InvocationError
  end

  class ExclusiveArgumentError < InvocationError
  end

  class AtLeastOneRequiredArgumentError < InvocationError
  end
end
