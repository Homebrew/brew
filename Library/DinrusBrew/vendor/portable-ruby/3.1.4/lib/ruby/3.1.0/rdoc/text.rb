# frozen_string_literal: true

##
# For RDoc::Text#to_html

require 'strscan'

##
# Methods for manipulating comment text

module RDoc::Text

  attr_accessor :language

  ##
  # Maps markup formats to classes that can parse them.  If the format is
  # unknown, "rdoc" format is used.

  MARKUP_FORMAT = {
    'markdown' => RDoc::Markdown,
    'rdoc'     => RDoc::Markup,
    'rd'       => RDoc::RD,
    'tomdoc'   => RDoc::TomDoc,
  }

  MARKUP_FORMAT.default = RDoc::Markup

  ##
  # Maps an encoding to a Hash of characters properly transcoded for that
  # encoding.
  #
  # See also encode_fallback.

  TO_HTML_CHARACTERS = Hash.new do |h, encoding|
    h[encoding] = {
      :close_dquote => encode_fallback('”', encoding, '"'),
      :close_squote => encode_fallback('’', encoding, '\''),
      :copyright    => encode_fallback('©', encoding, '(c)'),
      :ellipsis     => encode_fallback('…', encoding, '...'),
      :em_dash      => encode_fallback('—', encoding, '---'),
      :en_dash      => encode_fallback('–', encoding, '--'),
      :open_dquote  => encode_fallback('“', encoding, '"'),
      :open_squote  => encode_fallback('‘', encoding, '\''),
      :trademark    => encode_fallback('®', encoding, '(r)'),
    }
  end

  ##
  # Transcodes +character+ to +encoding+ with a +fallback+ character.

  def self.encode_fallback character, encoding, fallback
    character.encode(encoding, :fallback => { character => fallback },
                     :undef => :replace, :replace => fallback)
  end

  ##
  # Expands tab characters in +text+ to eight spaces

  def expand_tabs text
    expanded = []

    text.each_line do |line|
      nil while line.gsub!(/(?:\G|\r)((?:.{8})*?)([^\t\r\n]{0,7})\t/) do
        r = "#{$1}#{$2}#{' ' * (8 - $2.size)}"
        r = RDoc::Encoding.change_encoding r, text.encoding
        r
      end

      expanded << line
    end

    expanded.join
  end

  ##
  # Flush +text+ left based on the shortest line

  def flush_left text
    indent = 9999

    text.each_line do |line|
      line_indent = line =~ /\S/ || 9999
      indent = line_indent if indent > line_indent
    end

    empty = ''
    empty = RDoc::Encoding.change_encoding empty, text.encoding

    text.gsub(/^ {0,#{indent}}/, empty)
  end

  ##
  # Convert a string in markup format into HTML.
  #
  # Requires the including class to implement #formatter

  def markup text
    if @store.rdoc.options
      locale = @store.rdoc.options.locale
    else
      locale = nil
    end
    if locale
      i18n_text = RDoc::I18n::Text.new(text)
      text = i18n_text.translate(locale)
    end
    parse(text).accept formatter
  end

  ##
  # Strips hashes, expands tabs then flushes +text+ to the left

  def normalize_comment text
    return text if text.empty?

    case language
    when :ruby
      text = strip_hashes text
    when :c
      text = strip_stars text
    end
    text = expand_tabs    text
    text = flush_left     text
    text = strip_newlines text
    text
  end

  ##
  # Normalizes +text+ then builds a RDoc::Markup::Document from it

  def parse text, format = 'rdoc'
    return text if RDoc::Markup::Document === text
    return text.parse if RDoc::Comment === text

    text = normalize_comment text # TODO remove, should not be necessary

    return RDoc::Markup::Document.new if text =~ /\A\n*\z/

    MARKUP_FORMAT[format].parse text
  end

  ##
  # The first +limit+ characters of +text+ as HTML

  def snippet text, limit = 100
    document = parse text

    RDoc::Markup::ToHtmlSnippet.new(options, limit).convert document
  end

  ##
  # Strips leading # characters from +text+

  def strip_hashes text
    return text if text =~ /^(?>\s*)[^\#]/

    empty = ''
    empty = RDoc::Encoding.change_encoding empty, text.encoding

    text.gsub(/^\s*(#+)/) { $1.tr '#', ' ' }.gsub(/^\s+$/, empty)
  end

  ##
  # Strips leading and trailing \n characters from +text+

  def strip_newlines text
    text.gsub(/\A\n*(.*?)\n*\z/m) do $1 end # block preserves String encoding
  end

  ##
  # Strips /* */ style comments

  def strip_stars text
    return text unless text =~ %r%/\*.*\*/%m

    encoding = text.encoding

    text = text.gsub %r%Document-method:\s+[\w:.#=!?|^&<>~+\-/*\%@`\[\]]+%, ''

    space = ' '
    space = RDoc::Encoding.change_encoding space, encoding if encoding

    text.sub!  %r%/\*+%       do space * $&.length end
    text.sub!  %r%\*+/%       do space * $&.length end
    text.gsub! %r%^[ \t]*\*%m do space * $&.length end

    empty = ''
    empty = RDoc::Encoding.change_encoding empty, encoding if encoding
    text.gsub(/^\s+$/, empty)
  end

  ##
  # Converts ampersand, dashes, ellipsis, quotes, copyright and registered
  # trademark symbols in +text+ to properly encoded characters.

  def to_html text
    html = (''.encode text.encoding).dup

    encoded = RDoc::Text::TO_HTML_CHARACTERS[text.encoding]

    s = StringScanner.new text
    insquotes = false
    indquotes = false
    after_word = nil

    until s.eos? do
      case
      when s.scan(/<(tt|code)>.*?<\/\1>/) then # skip contents of tt
        html << s.matched.gsub('\\\\', '\\')
      when s.scan(/<(tt|code)>.*?/) then
        warn "mismatched <#{s[1]}> tag" # TODO signal file/line
        html << s.matched
      when s.scan(/<[^>]+\/?s*>/) then # skip HTML tags
        html << s.matched
      when s.scan(/\\(\S)/) then # unhandled suppressed crossref
        html << s[1]
        after_word = nil
      when s.scan(/\.\.\.(\.?)/) then
        html << s[1] << encoded[:ellipsis]
        after_word = nil
      when s.scan(/\(c\)/i) then
        html << encoded[:copyright]
        after_word = nil
      when s.scan(/\(r\)/i) then
        html << encoded[:trademark]
        after_word = nil
      when s.scan(/---/) then
        html << encoded[:em_dash]
        after_word = nil
      when s.scan(/--/) then
        html << encoded[:en_dash]
        after_word = nil
      when s.scan(/&quot;|"/) then
        html << encoded[indquotes ? :close_dquote : :open_dquote]
        indquotes = !indquotes
        after_word = nil
      when s.scan(/``/) then # backtick double quote
        html << encoded[:open_dquote]
        after_word = nil
      when s.scan(/(?:&#39;|'){2}/) then # tick double quote
        html << encoded[:close_dquote]
        after_word = nil
      when s.scan(/`/) then # backtick
        if insquotes or after_word
          html << '`'
          after_word = false
        else
          html << encoded[:open_squote]
          insquotes = true
        end
      when s.scan(/&#39;|'/) then # single quote
        if insquotes
          html << encoded[:close_squote]
          insquotes = false
        elsif after_word
          # Mary's dog, my parents' house: do not start paired quotes
          html << encoded[:close_squote]
        else
          html << encoded[:open_squote]
          insquotes = true
        end

        after_word = nil
      else # advance to the next potentially significant character
        match = s.scan(/.+?(?=[<\\.("'`&-])/) #"

        if match then
          html << match
          after_word = match =~ /\w$/
        else
          html << s.rest
          break
        end
      end
    end

    html
  end

  ##
  # Wraps +txt+ to +line_len+

  def wrap(txt, line_len = 76)
    res = []
    sp = 0
    ep = txt.length

    while sp < ep
      # scan back for a space
      p = sp + line_len - 1
      if p >= ep
        p = ep
      else
        while p > sp and txt[p] != ?\s
          p -= 1
        end
        if p <= sp
          p = sp + line_len
          while p < ep and txt[p] != ?\s
            p += 1
          end
        end
      end
      res << txt[sp...p] << "\n"
      sp = p
      sp += 1 while sp < ep and txt[sp] == ?\s
    end

    res.join.strip
  end

end
