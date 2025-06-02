# frozen_string_literal: true

require 'io/console/size'
require_relative 'console'

module DEBUGGER__
  class UI_LocalConsole < UI_Base
    def initialize
      @console = Console.new
    end

    def remote?
      false
    end

    def activate_sigint
      prev_handler = trap(:SIGINT){
        if SESSION.active?
          ThreadClient.current.on_trap :SIGINT
        end
      }
      SESSION.intercept_trap_sigint_start prev_handler
    end

    def deactivate_sigint
      if SESSION.intercept_trap_sigint?
        prev = SESSION.intercept_trap_sigint_end
        trap(:SIGINT, prev)
      end
    end

    def activate session, on_fork: false
      activate_sigint unless CONFIG[:no_sigint_hook]
    end

    def deactivate
      deactivate_sigint
      @console.deactivate
    end

    def width
      if (w = IO.console_size[1]) == 0 # for tests PTY
        80
      else
        w
      end
    end

    def quit n
      yield
      exit n
    end

    def ask prompt
      setup_interrupt do
        print prompt
        ($stdin.gets || '').strip
      end
    end

    def puts str = nil
      case str
      when Array
        str.each{|line|
          $stdout.puts line.chomp
        }
      when String
        str.each_line{|line|
          $stdout.puts line.chomp
        }
      when nil
        $stdout.puts
      end
    end

    def readline prompt = '(rdbg)'
      setup_interrupt do
        (@console.readline(prompt) || 'quit').strip
      end
    end

    def setup_interrupt
      SESSION.intercept_trap_sigint false do
        current_thread = Thread.current # should be session_server thread

        prev_handler = trap(:INT){
          current_thread.raise Interrupt
        }

        yield
      ensure
        trap(:INT, prev_handler)
      end
    end

    def after_fork_parent
      parent_pid = Process.pid

      at_exit{
        SESSION.intercept_trap_sigint_end
        trap(:SIGINT, :IGNORE)

        if Process.pid == parent_pid
          # only check child process from its parent
          begin
            # wait for all child processes to keep terminal
            Process.waitpid
          rescue Errno::ESRCH, Errno::ECHILD
          end
        end
      }
    end
  end
end

