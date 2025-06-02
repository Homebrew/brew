# frozen_string_literal: true

module Bundler
  module UI
    class Silent
      attr_writer :shell

      def initialize
        @warnings = []
      end

      def add_color(string, color)
        string
      end

      def info(message = nil, newline = nil)
      end

      def confirm(message = nil, newline = nil)
      end

      def warn(message = nil, newline = nil)
        @warnings |= [message]
      end

      def error(message = nil, newline = nil)
      end

      def debug(message = nil, newline = nil)
      end

      def confirm?
        false
      end

      def error?
        false
      end

      def debug?
        false
      end

      def info?
        false
      end

      def quiet?
        false
      end

      def warn?
        false
      end

      def output_stream=(_symbol)
      end

      def output_stream
        nil
      end

      def ask(message)
      end

      def yes?(msg)
        raise "Cannot ask yes? with a silent shell"
      end

      def no?(msg)
        raise "Cannot ask no? with a silent shell"
      end

      def level=(name)
      end

      def level(name = nil)
      end

      def trace(message, newline = nil, force = false)
      end

      def silence
        yield
      end

      def progress
        yield
      end

      def unprinted_warnings
        @warnings
      end
    end
  end
end
