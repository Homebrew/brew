# frozen_string_literal: true
##
# A TokenStream is a list of tokens, gathered during the parse of some entity
# (say a method). Entities populate these streams by being registered with the
# lexer. Any class can collect tokens by including TokenStream. From the
# outside, you use such an object by calling the start_collecting_tokens
# method, followed by calls to add_token and pop_token.

module RDoc::TokenStream

  ##
  # Converts +token_stream+ to HTML wrapping various tokens with
  # <tt><span></tt> elements. Some tokens types are wrapped in spans
  # with the given class names. Other token types are not wrapped in spans.

  def self.to_html token_stream
    starting_title = false

    token_stream.map do |t|
      next unless t

      style = case t[:kind]
              when :on_const   then 'ruby-constant'
              when :on_kw      then 'ruby-keyword'
              when :on_ivar    then 'ruby-ivar'
              when :on_cvar    then 'ruby-identifier'
              when :on_gvar    then 'ruby-identifier'
              when '=' != t[:text] && :on_op
                               then 'ruby-operator'
              when :on_tlambda then 'ruby-operator'
              when :on_ident   then 'ruby-identifier'
              when :on_label   then 'ruby-value'
              when :on_backref, :on_dstring
                               then 'ruby-node'
              when :on_comment then 'ruby-comment'
              when :on_embdoc  then 'ruby-comment'
              when :on_regexp  then 'ruby-regexp'
              when :on_tstring then 'ruby-string'
              when :on_int, :on_float,
                   :on_rational, :on_imaginary,
                   :on_heredoc,
                   :on_symbol, :on_CHAR then 'ruby-value'
              when :on_heredoc_beg, :on_heredoc_end
                               then 'ruby-identifier'
              end

      comment_with_nl = false
      if :on_comment == t[:kind] or :on_embdoc == t[:kind] or :on_heredoc_end == t[:kind]
        comment_with_nl = true if "\n" == t[:text][-1]
        text = t[:text].rstrip
      else
        text = t[:text]
      end

      if :on_ident == t[:kind] && starting_title
        starting_title = false
        style = 'ruby-identifier ruby-title'
      end

      if :on_kw == t[:kind] and 'def' == t[:text]
        starting_title = true
      end

      text = CGI.escapeHTML text

      if style then
        "<span class=\"#{style}\">#{text}</span>#{"\n" if comment_with_nl}"
      else
        text
      end
    end.join
  end

  ##
  # Adds +tokens+ to the collected tokens

  def add_tokens(tokens)
    @token_stream.concat(tokens)
  end

  ##
  # Adds one +token+ to the collected tokens

  def add_token(token)
    @token_stream.push(token)
  end

  ##
  # Starts collecting tokens

  def collect_tokens
    @token_stream = []
  end

  alias start_collecting_tokens collect_tokens

  ##
  # Remove the last token from the collected tokens

  def pop_token
    @token_stream.pop
  end

  ##
  # Current token stream

  def token_stream
    @token_stream
  end

  ##
  # Returns a string representation of the token stream

  def tokens_to_s
    (token_stream or return '').compact.map { |token| token[:text] }.join ''
  end

end
