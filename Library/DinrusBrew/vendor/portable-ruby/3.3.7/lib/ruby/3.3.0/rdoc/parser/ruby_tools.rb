# frozen_string_literal: true
##
# Collection of methods for writing parsers

module RDoc::Parser::RubyTools

  ##
  # Adds a token listener +obj+, but you should probably use token_listener

  def add_token_listener(obj)
    @token_listeners ||= []
    @token_listeners << obj
  end

  ##
  # Fetches the next token from the scanner

  def get_tk
    tk = nil

    if @tokens.empty? then
      if @scanner_point >= @scanner.size
        return nil
      else
        tk = @scanner[@scanner_point]
        @scanner_point += 1
        @read.push tk[:text]
      end
    else
      @read.push @unget_read.shift
      tk = @tokens.shift
    end

    if tk == nil || :on___end__ == tk[:kind]
      tk = nil
    end

    return nil unless tk

    # inform any listeners of our shiny new token
    @token_listeners.each do |obj|
      obj.add_token(tk)
    end if @token_listeners

    tk
  end

  ##
  # Reads and returns all tokens up to one of +tokens+.  Leaves the matched
  # token in the token list.

  def get_tk_until(*tokens)
    read = []

    loop do
      tk = get_tk

      case tk
      when *tokens then
        unget_tk tk
        break
      end

      read << tk
    end

    read
  end

  ##
  # Retrieves a String representation of the read tokens

  def get_tkread
    read = @read.join("")
    @read = []
    read
  end

  ##
  # Peek equivalent for get_tkread

  def peek_read
    @read.join('')
  end

  ##
  # Peek at the next token, but don't remove it from the stream

  def peek_tk
    unget_tk(tk = get_tk)
    tk
  end

  ##
  # Removes the token listener +obj+

  def remove_token_listener(obj)
    @token_listeners.delete(obj)
  end

  ##
  # Resets the tools

  def reset
    @read       = []
    @tokens     = []
    @unget_read = []
    @nest = 0
    @scanner_point = 0
  end

  ##
  # Skips whitespace tokens including newlines

  def skip_tkspace
    tokens = []

    while (tk = get_tk) and (:on_sp == tk[:kind] or :on_nl == tk[:kind] or :on_ignored_nl == tk[:kind]) do
      tokens.push(tk)
    end

    unget_tk(tk)
    tokens
  end

  ##
  # Skips whitespace tokens excluding newlines

  def skip_tkspace_without_nl
    tokens = []

    while (tk = get_tk) and :on_sp == tk[:kind] do
      tokens.push(tk)
    end

    unget_tk(tk)
    tokens
  end

  ##
  # Has +obj+ listen to tokens

  def token_listener(obj)
    add_token_listener obj
    yield
  ensure
    remove_token_listener obj
  end

  ##
  # Returns +tk+ to the scanner

  def unget_tk(tk)
    @tokens.unshift tk
    @unget_read.unshift @read.pop

    # Remove this token from any listeners
    @token_listeners.each do |obj|
      obj.pop_token
    end if @token_listeners

    nil
  end

end
