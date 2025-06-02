# frozen_string_literal: true

module SyntaxSuggest
  # Converts a SyntaxError message to a path
  #
  # Handles the case where the filename has a colon in it
  # such as on a windows file system: https://github.com/ruby/syntax_suggest/issues/111
  #
  # Example:
  #
  #    message = "/tmp/scratch:2:in `require_relative': /private/tmp/bad.rb:1: syntax error, unexpected `end' (SyntaxError)"
  #    puts PathnameFromMessage.new(message).call.name
  #    # => "/tmp/scratch.rb"
  #
  class PathnameFromMessage
    EVAL_RE = /^\(eval.*\):\d+/
    STREAMING_RE = /^-:\d+/
    attr_reader :name

    def initialize(message, io: $stderr)
      @line = message.lines.first
      @parts = @line.split(":")
      @guess = []
      @name = nil
      @io = io
    end

    def call
      if skip_missing_file_name?
        if ENV["SYNTAX_SUGGEST_DEBUG"]
          @io.puts "SyntaxSuggest: Could not find filename from #{@line.inspect}"
        end
      else
        until stop?
          @guess << @parts.shift
          @name = Pathname(@guess.join(":"))
        end

        if @parts.empty?
          @io.puts "SyntaxSuggest: Could not find filename from #{@line.inspect}"
          @name = nil
        end
      end

      self
    end

    def stop?
      return true if @parts.empty?
      return false if @guess.empty?

      @name&.exist?
    end

    def skip_missing_file_name?
      @line.match?(EVAL_RE) || @line.match?(STREAMING_RE)
    end
  end
end
