# frozen_string_literal: true

require_relative "../vendored_thor"

module Bundler
  module UI
    class Shell
      LEVELS = %w[silent error warn confirm info debug].freeze
      OUTPUT_STREAMS = [:stdout, :stderr].freeze

      attr_writer :shell
      attr_reader :output_stream

      def initialize(options = {})
        Thor::Base.shell = options["no-color"] ? Thor::Shell::Basic : nil
        @shell = Thor::Base.shell.new
        @level = ENV["DEBUG"] ? "debug" : "info"
        @warning_history = []
        @output_stream = :stdout
      end

      def add_color(string, *color)
        @shell.set_color(string, *color)
      end

      def info(msg = nil, newline = nil)
        return unless info?

        tell_me(msg || yield, nil, newline)
      end

      def confirm(msg = nil, newline = nil)
        return unless confirm?

        tell_me(msg || yield, :green, newline)
      end

      def warn(msg = nil, newline = nil, color = :yellow)
        return unless warn?
        return if @warning_history.include? msg
        @warning_history << msg

        tell_err(msg || yield, color, newline)
      end

      def error(msg = nil, newline = nil, color = :red)
        return unless error?

        tell_err(msg || yield, color, newline)
      end

      def debug(msg = nil, newline = nil)
        return unless debug?

        tell_me(msg || yield, nil, newline)
      end

      def info?
        level("info")
      end

      def confirm?
        level("confirm")
      end

      def warn?
        level("warn")
      end

      def error?
        level("error")
      end

      def debug?
        level("debug")
      end

      def quiet?
        level("quiet")
      end

      def ask(msg)
        @shell.ask(msg)
      end

      def yes?(msg)
        @shell.yes?(msg)
      end

      def no?(msg)
        @shell.no?(msg)
      end

      def level=(level)
        raise ArgumentError unless LEVELS.include?(level.to_s)
        @level = level.to_s
      end

      def level(name = nil)
        return @level unless name
        unless index = LEVELS.index(name)
          raise "#{name.inspect} is not a valid level"
        end
        index <= LEVELS.index(@level)
      end

      def output_stream=(symbol)
        raise ArgumentError unless OUTPUT_STREAMS.include?(symbol)
        @output_stream = symbol
      end

      def trace(e, newline = nil, force = false)
        return unless debug? || force
        msg = "#{e.class}: #{e.message}\n#{e.backtrace.join("\n  ")}"
        tell_err(msg, nil, newline)
      end

      def silence(&blk)
        with_level("silent", &blk)
      end

      def progress(&blk)
        with_output_stream(:stderr, &blk)
      end

      def unprinted_warnings
        []
      end

      private

      # valimism
      def tell_me(msg, color = nil, newline = nil)
        return tell_err(msg, color, newline) if output_stream == :stderr

        msg = word_wrap(msg) if newline.is_a?(Hash) && newline[:wrap]
        if newline.nil?
          @shell.say(msg, color)
        else
          @shell.say(msg, color, newline)
        end
      end

      def tell_err(message, color = nil, newline = nil)
        return if @shell.send(:stderr).closed?

        newline = !message.to_s.match?(/( |\t)\Z/) if newline.nil?
        message = word_wrap(message) if newline.is_a?(Hash) && newline[:wrap]

        color = nil if color && !$stderr.tty?

        buffer = @shell.send(:prepare_message, message, *color)
        buffer << "\n" if newline && !message.to_s.end_with?("\n")

        @shell.send(:stderr).print(buffer)
        @shell.send(:stderr).flush
      end

      def strip_leading_spaces(text)
        spaces = text[/\A\s+/, 0]
        spaces ? text.gsub(/#{spaces}/, "") : text
      end

      def word_wrap(text, line_width = Thor::Terminal.terminal_width)
        strip_leading_spaces(text).split("\n").collect do |line|
          line.length > line_width ? line.gsub(/(.{1,#{line_width}})(\s+|$)/, "\\1\n").strip : line
        end * "\n"
      end

      def with_level(level)
        original = @level
        @level = level
        yield
      ensure
        @level = original
      end

      def with_output_stream(symbol)
        original = output_stream
        self.output_stream = symbol
        yield
      ensure
        @output_stream = original
      end
    end
  end
end
