# frozen_string_literal: true
#
#   multi.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB
  # :stopdoc:

  module Command
    class MultiIRBCommand < Base
      include RubyArgsExtractor

      private

      def print_deprecated_warning
        warn <<~MSG
          Multi-irb commands are deprecated and will be removed in IRB 2.0.0. Please use workspace commands instead.
          If you have any use case for multi-irb, please leave a comment at https://github.com/ruby/irb/issues/653
        MSG
      end

      def extend_irb_context
        # this extension patches IRB context like IRB.CurrentContext
        require_relative "../ext/multi-irb"
      end

      def print_debugger_warning
        warn "Multi-IRB commands are not available when the debugger is enabled."
      end
    end

    class IrbCommand < MultiIRBCommand
      category "Multi-irb (DEPRECATED)"
      description "Start a child IRB."

      def execute(arg)
        args, kwargs = ruby_args(arg)
        execute_internal(*args, **kwargs)
      end

      def execute_internal(*obj)
        print_deprecated_warning

        if irb_context.with_debugger
          print_debugger_warning
          return
        end

        extend_irb_context
        IRB.irb(nil, *obj)
        puts IRB.JobManager.inspect
      end
    end

    class Jobs < MultiIRBCommand
      category "Multi-irb (DEPRECATED)"
      description "List of current sessions."

      def execute(_arg)
        print_deprecated_warning

        if irb_context.with_debugger
          print_debugger_warning
          return
        end

        extend_irb_context
        puts IRB.JobManager.inspect
      end
    end

    class Foreground < MultiIRBCommand
      category "Multi-irb (DEPRECATED)"
      description "Switches to the session of the given number."

      def execute(arg)
        args, kwargs = ruby_args(arg)
        execute_internal(*args, **kwargs)
      end

      def execute_internal(key = nil)
        print_deprecated_warning

        if irb_context.with_debugger
          print_debugger_warning
          return
        end

        extend_irb_context

        raise CommandArgumentError.new("Please specify the id of target IRB job (listed in the `jobs` command).") unless key
        IRB.JobManager.switch(key)
        puts IRB.JobManager.inspect
      end
    end

    class Kill < MultiIRBCommand
      category "Multi-irb (DEPRECATED)"
      description "Kills the session with the given number."

      def execute(arg)
        args, kwargs = ruby_args(arg)
        execute_internal(*args, **kwargs)
      end

      def execute_internal(*keys)
        print_deprecated_warning

        if irb_context.with_debugger
          print_debugger_warning
          return
        end

        extend_irb_context
        IRB.JobManager.kill(*keys)
        puts IRB.JobManager.inspect
      end
    end
  end

  # :startdoc:
end
