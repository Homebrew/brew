# frozen_string_literal: true

module SyntaxSuggest
  # Capture parse errors from Ripper
  #
  # Prism returns the errors with their messages, but Ripper
  # does not. To get them we must make a custom subclass.
  #
  # Example:
  #
  #   puts RipperErrors.new(" def foo").call.errors
  #   # => ["syntax error, unexpected end-of-input, expecting ';' or '\\n'"]
  class RipperErrors < Ripper
    attr_reader :errors

    # Comes from ripper, called
    # on every parse error, msg
    # is a string
    def on_parse_error(msg)
      @errors ||= []
      @errors << msg
    end

    alias_method :on_alias_error, :on_parse_error
    alias_method :on_assign_error, :on_parse_error
    alias_method :on_class_name_error, :on_parse_error
    alias_method :on_param_error, :on_parse_error
    alias_method :compile_error, :on_parse_error

    def call
      @run_once ||= begin
        @errors = []
        parse
        true
      end
      self
    end
  end
end
