# frozen_string_literal: true

begin
  require 'irb/color'

  module IRB
    module Color
      DIM = 2 unless defined? DIM
    end
  end

  require "irb/color_printer"
rescue LoadError
  warn "DEBUGGER: can not load newer irb for coloring. Write 'gem \"debug\" in your Gemfile."
end

module DEBUGGER__
  module Color
    if defined? IRB::Color.colorize
      begin
        IRB::Color.colorize('', [:DIM], colorable: true)
        SUPPORT_COLORABLE_OPTION = true
      rescue ArgumentError
      end

      if defined? SUPPORT_COLORABLE_OPTION
        def irb_colorize str, color
          IRB::Color.colorize str, color, colorable: true
        end
      else
        def irb_colorize str, color
          IRB::Color.colorize str, color
        end
      end

      def colorize str, color
        if !CONFIG[:no_color]
          irb_colorize str, color
        else
          str
        end
      end
    else
      def colorize str, color
        str
      end
    end

    if defined? IRB::ColorPrinter.pp
      def color_pp obj, width
        with_inspection_error_guard do
          if !CONFIG[:no_color]
            IRB::ColorPrinter.pp(obj, "".dup, width)
          else
            obj.pretty_inspect
          end
        end
      end
    else
      def color_pp obj, width
        with_inspection_error_guard do
          obj.pretty_inspect
        end
      end
    end

    def colored_inspect obj, width: SESSION.width, no_color: false
      with_inspection_error_guard do
        if !no_color
          color_pp obj, width
        else
          obj.pretty_inspect
        end
      end
    end

    if defined? IRB::Color.colorize_code
      if defined? SUPPORT_COLORABLE_OPTION
        def colorize_code code
          IRB::Color.colorize_code(code, colorable: true)
        end
      else
        def colorize_code code
          IRB::Color.colorize_code(code)
        end
      end
    else
      def colorize_code code
        code
      end
    end

    def colorize_cyan(str)
      colorize(str, [:CYAN, :BOLD])
    end

    def colorize_blue(str)
      colorize(str, [:BLUE, :BOLD])
    end

    def colorize_magenta(str)
      colorize(str, [:MAGENTA, :BOLD])
    end

    def colorize_dim(str)
      colorize(str, [:DIM])
    end

    def with_inspection_error_guard
      yield
    rescue Exception => ex
      err_msg = "#{ex.inspect} rescued during inspection"
      string_result = obj.to_s rescue nil

      # don't colorize the string here because it's not from user's application
      if string_result
        %Q{"#{string_result}" from #to_s because #{err_msg}}
      else
        err_msg
      end
    end
  end
end
