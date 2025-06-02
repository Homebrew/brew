# frozen_string_literal: true
module Psych
  ###
  # YAML event parser class.  This class parses a YAML document and calls
  # events on the handler that is passed to the constructor.  The events can
  # be used for things such as constructing a YAML AST or deserializing YAML
  # documents.  It can even be fed back to Psych::Emitter to emit the same
  # document that was parsed.
  #
  # See Psych::Handler for documentation on the events that Psych::Parser emits.
  #
  # Here is an example that prints out ever scalar found in a YAML document:
  #
  #   # Handler for detecting scalar values
  #   class ScalarHandler < Psych::Handler
  #     def scalar value, anchor, tag, plain, quoted, style
  #       puts value
  #     end
  #   end
  #
  #   parser = Psych::Parser.new(ScalarHandler.new)
  #   parser.parse(yaml_document)
  #
  # Here is an example that feeds the parser back in to Psych::Emitter.  The
  # YAML document is read from STDIN and written back out to STDERR:
  #
  #   parser = Psych::Parser.new(Psych::Emitter.new($stderr))
  #   parser.parse($stdin)
  #
  # Psych uses Psych::Parser in combination with Psych::TreeBuilder to
  # construct an AST of the parsed YAML document.

  class Parser
    class Mark < Struct.new(:index, :line, :column)
    end

    # The handler on which events will be called
    attr_accessor :handler

    # Set the encoding for this parser to +encoding+
    attr_writer :external_encoding

    ###
    # Creates a new Psych::Parser instance with +handler+.  YAML events will
    # be called on +handler+.  See Psych::Parser for more details.

    def initialize handler = Handler.new
      @handler = handler
      @external_encoding = ANY
    end
  end
end
