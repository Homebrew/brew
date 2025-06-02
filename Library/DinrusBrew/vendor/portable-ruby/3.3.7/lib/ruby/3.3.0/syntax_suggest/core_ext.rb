# frozen_string_literal: true

# Ruby 3.2+ has a cleaner way to hook into Ruby that doesn't use `require`
if SyntaxError.method_defined?(:detailed_message)
  module SyntaxSuggest
    # Mini String IO [Private]
    #
    # Acts like a StringIO with reduced API, but without having to require that
    # class.
    class MiniStringIO
      def initialize(isatty: $stderr.isatty)
        @string = +""
        @isatty = isatty
      end

      attr_reader :isatty
      def puts(value = $/, **)
        @string << value
      end

      attr_reader :string
    end

    # SyntaxSuggest.module_for_detailed_message [Private]
    #
    # Used to monkeypatch SyntaxError via Module.prepend
    def self.module_for_detailed_message
      Module.new {
        def detailed_message(highlight: true, syntax_suggest: true, **kwargs)
          return super unless syntax_suggest

          require "syntax_suggest/api" unless defined?(SyntaxSuggest::DEFAULT_VALUE)

          message = super

          if path
            file = Pathname.new(path)
            io = SyntaxSuggest::MiniStringIO.new

            SyntaxSuggest.call(
              io: io,
              source: file.read,
              filename: file,
              terminal: highlight
            )
            annotation = io.string

            annotation += "\n" unless annotation.end_with?("\n")

            annotation + message
          else
            message
          end
        rescue => e
          if ENV["SYNTAX_SUGGEST_DEBUG"]
            $stderr.warn(e.message)
            $stderr.warn(e.backtrace)
          end

          # Ignore internal errors
          message
        end
      }
    end
  end

  SyntaxError.prepend(SyntaxSuggest.module_for_detailed_message)
else
  autoload :Pathname, "pathname"

  #--
  # Monkey patch kernel to ensure that all `require` calls call the same
  # method
  #++
  module Kernel
    # :stopdoc:

    module_function

    alias_method :syntax_suggest_original_require, :require
    alias_method :syntax_suggest_original_require_relative, :require_relative
    alias_method :syntax_suggest_original_load, :load

    def load(file, wrap = false)
      syntax_suggest_original_load(file)
    rescue SyntaxError => e
      require "syntax_suggest/api" unless defined?(SyntaxSuggest::DEFAULT_VALUE)

      SyntaxSuggest.handle_error(e)
    end

    def require(file)
      syntax_suggest_original_require(file)
    rescue SyntaxError => e
      require "syntax_suggest/api" unless defined?(SyntaxSuggest::DEFAULT_VALUE)

      SyntaxSuggest.handle_error(e)
    end

    def require_relative(file)
      if Pathname.new(file).absolute?
        syntax_suggest_original_require file
      else
        relative_from = caller_locations(1..1).first
        relative_from_path = relative_from.absolute_path || relative_from.path
        syntax_suggest_original_require File.expand_path("../#{file}", relative_from_path)
      end
    rescue SyntaxError => e
      require "syntax_suggest/api" unless defined?(SyntaxSuggest::DEFAULT_VALUE)

      SyntaxSuggest.handle_error(e)
    end
  end
end
