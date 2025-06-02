
module Reline
  class IO
    RESET_COLOR = "\e[0m"

    def self.decide_io_gate
      if ENV['TERM'] == 'dumb'
        Reline::Dumb.new
      else
        require 'reline/io/ansi'

        case RbConfig::CONFIG['host_os']
        when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
          require 'reline/io/windows'
          io = Reline::Windows.new
          if io.msys_tty?
            Reline::ANSI.new
          else
            io
          end
        else
          Reline::ANSI.new
        end
      end
    end

    def dumb?
      false
    end

    def win?
      false
    end

    def reset_color_sequence
      self.class::RESET_COLOR
    end
  end
end

require 'reline/io/dumb'
