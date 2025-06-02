require 'io/console/size'
require 'debug/console'

module IRB
  module Debug
    class UI < DEBUGGER__::UI_Base
      def initialize(irb)
        @irb = irb
      end

      def remote?
        false
      end

      def activate session, on_fork: false
      end

      def deactivate
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

      def readline _
        setup_interrupt do
          tc = DEBUGGER__::SESSION.instance_variable_get(:@tc)
          cmd = @irb.debug_readline(tc.current_frame.binding || TOPLEVEL_BINDING)

          case cmd
          when nil # when user types C-d
            "continue"
          else
            cmd
          end
        end
      end

      def setup_interrupt
        DEBUGGER__::SESSION.intercept_trap_sigint false do
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
          DEBUGGER__::SESSION.intercept_trap_sigint_end
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
end
