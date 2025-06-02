# frozen_string_literal: true
require 'pp'
require_relative 'color'

module IRB
  class ColorPrinter < ::PP
    METHOD_RESPOND_TO = Object.instance_method(:respond_to?)
    METHOD_INSPECT = Object.instance_method(:inspect)

    class << self
      def pp(obj, out = $>, width = screen_width)
        q = ColorPrinter.new(out, width)
        q.guard_inspect_key {q.pp obj}
        q.flush
        out << "\n"
      end

      private

      def screen_width
        Reline.get_screen_size.last
      rescue Errno::EINVAL # in `winsize': Invalid argument - <STDIN>
        79
      end
    end

    def pp(obj)
      if String === obj
        # Avoid calling Ruby 2.4+ String#pretty_print that splits a string by "\n"
        text(obj.inspect)
      elsif !METHOD_RESPOND_TO.bind(obj).call(:inspect)
        text(METHOD_INSPECT.bind(obj).call)
      else
        super
      end
    end

    def text(str, width = nil)
      unless str.is_a?(String)
        str = str.inspect
      end
      width ||= str.length

      case str
      when ''
      when ',', '=>', '[', ']', '{', '}', '..', '...', /\A@\w+\z/
        super(str, width)
      when /\A#</, '=', '>'
        super(Color.colorize(str, [:GREEN]), width)
      else
        super(Color.colorize_code(str, ignore_error: true), width)
      end
    end
  end
end
