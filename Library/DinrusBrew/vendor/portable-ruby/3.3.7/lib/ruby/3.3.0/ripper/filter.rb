# frozen_string_literal: true
#
# $Id$
#
# Copyright (c) 2004,2005 Minero Aoki
#
# This program is free software.
# You can distribute and/or modify this program under the Ruby License.
# For details of Ruby License, see ruby/COPYING.
#

require 'ripper/lexer'

class Ripper

  # This class handles only scanner events,
  # which are dispatched in the 'right' order (same with input).
  class Filter

    # Creates a new Ripper::Filter instance, passes parameters +src+,
    # +filename+, and +lineno+ to Ripper::Lexer.new
    #
    # The lexer is for internal use only.
    def initialize(src, filename = '-', lineno = 1)
      @__lexer = Lexer.new(src, filename, lineno)
      @__line = nil
      @__col = nil
      @__state = nil
    end

    # The file name of the input.
    def filename
      @__lexer.filename
    end

    # The line number of the current token.
    # This value starts from 1.
    # This method is valid only in event handlers.
    def lineno
      @__line
    end

    # The column number of the current token.
    # This value starts from 0.
    # This method is valid only in event handlers.
    def column
      @__col
    end

    # The scanner's state of the current token.
    # This value is the bitwise OR of zero or more of the +Ripper::EXPR_*+ constants.
    def state
      @__state
    end

    # Starts the parser.
    # +init+ is a data accumulator and is passed to the next event handler (as
    # of Enumerable#inject).
    def parse(init = nil)
      data = init
      @__lexer.lex.each do |pos, event, tok, state|
        @__line, @__col = *pos
        @__state = state
        data = if respond_to?(event, true)
               then __send__(event, tok, data)
               else on_default(event, tok, data)
               end
      end
      data
    end

    private

    # This method is called when some event handler is undefined.
    # +event+ is :on_XXX, +token+ is the scanned token, and +data+ is a data
    # accumulator.
    #
    # The return value of this method is passed to the next event handler (as
    # of Enumerable#inject).
    def on_default(event, token, data)
      data
    end

  end

end
