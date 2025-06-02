class Bundler::Thor
  module Shell
    module Terminal
      DEFAULT_TERMINAL_WIDTH = 80

      class << self
        # This code was copied from Rake, available under MIT-LICENSE
        # Copyright (c) 2003, 2004 Jim Weirich
        def terminal_width
          result = if ENV["THOR_COLUMNS"]
            ENV["THOR_COLUMNS"].to_i
          else
            unix? ? dynamic_width : DEFAULT_TERMINAL_WIDTH
          end
          result < 10 ? DEFAULT_TERMINAL_WIDTH : result
        rescue
          DEFAULT_TERMINAL_WIDTH
        end

        def unix?
          RUBY_PLATFORM =~ /(aix|darwin|linux|(net|free|open)bsd|cygwin|solaris)/i
        end

      private

        # Calculate the dynamic width of the terminal
        def dynamic_width
          @dynamic_width ||= (dynamic_width_stty.nonzero? || dynamic_width_tput)
        end

        def dynamic_width_stty
          `stty size 2>/dev/null`.split[1].to_i
        end

        def dynamic_width_tput
          `tput cols 2>/dev/null`.to_i
        end

      end
    end
  end
end
