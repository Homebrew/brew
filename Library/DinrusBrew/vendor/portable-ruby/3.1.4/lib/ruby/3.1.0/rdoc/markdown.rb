# coding: UTF-8
# frozen_string_literal: true
# :markup: markdown

##
# RDoc::Markdown as described by the [markdown syntax][syntax].
#
# To choose Markdown as your only default format see
# RDoc::Options@Saved+Options for instructions on setting up a `.doc_options`
# file to store your project default.
#
# ## Usage
#
# Here is a brief example of using this parse to read a markdown file by hand.
#
#     data = File.read("README.md")
#     formatter = RDoc::Markup::ToHtml.new(RDoc::Options.new, nil)
#     html = RDoc::Markdown.parse(data).accept(formatter)
#
#     # do something with html
#
# ## Extensions
#
# The following markdown extensions are supported by the parser, but not all
# are used in RDoc output by default.
#
# ### RDoc
#
# The RDoc Markdown parser has the following built-in behaviors that cannot be
# disabled.
#
# Underscores embedded in words are never interpreted as emphasis.  (While the
# [markdown dingus][dingus] emphasizes in-word underscores, neither the
# Markdown syntax nor MarkdownTest mention this behavior.)
#
# For HTML output, RDoc always auto-links bare URLs.
#
# ### Break on Newline
#
# The break_on_newline extension converts all newlines into hard line breaks
# as in [Github Flavored Markdown][GFM].  This extension is disabled by
# default.
#
# ### CSS
#
# The #css extension enables CSS blocks to be included in the output, but they
# are not used for any built-in RDoc output format.  This extension is disabled
# by default.
#
# Example:
#
#     <style type="text/css">
#     h1 { font-size: 3em }
#     </style>
#
# ### Definition Lists
#
# The definition_lists extension allows definition lists using the [PHP
# Markdown Extra syntax][PHPE], but only one label and definition are supported
# at this time.  This extension is enabled by default.
#
# Example:
#
# ```
# cat
# :   A small furry mammal
# that seems to sleep a lot
#
# ant
# :   A little insect that is known
# to enjoy picnics
#
# ```
#
# Produces:
#
# cat
# :   A small furry mammal
# that seems to sleep a lot
#
# ant
# :   A little insect that is known
# to enjoy picnics
#
# ### Strike
#
# Example:
#
# ```
# This is ~~striked~~.
# ```
#
# Produces:
#
# This is ~~striked~~.
#
# ### Github
#
# The #github extension enables a partial set of [Github Flavored Markdown]
# [GFM].  This extension is enabled by default.
#
# Supported github extensions include:
#
# #### Fenced code blocks
#
# Use ` ``` ` around a block of code instead of indenting it four spaces.
#
# #### Syntax highlighting
#
# Use ` ``` ruby ` as the start of a code fence to add syntax highlighting.
# (Currently only `ruby` syntax is supported).
#
# ### HTML
#
# Enables raw HTML to be included in the output.  This extension is enabled by
# default.
#
# Example:
#
#     <table>
#     ...
#     </table>
#
# ### Notes
#
# The #notes extension enables footnote support.  This extension is enabled by
# default.
#
# Example:
#
#     Here is some text[^1] including an inline footnote ^[for short footnotes]
#
#     ...
#
#     [^1]: With the footnote text down at the bottom
#
# Produces:
#
# Here is some text[^1] including an inline footnote ^[for short footnotes]
#
# [^1]: With the footnote text down at the bottom
#
# ## Limitations
#
# * Link titles are not used
# * Footnotes are collapsed into a single paragraph
#
# ## Author
#
# This markdown parser is a port to kpeg from [peg-markdown][pegmarkdown] by
# John MacFarlane.
#
# It is used under the MIT license:
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# The port to kpeg was performed by Eric Hodel and Evan Phoenix
#
# [dingus]: http://daringfireball.net/projects/markdown/dingus
# [GFM]: https://github.github.com/gfm/
# [pegmarkdown]: https://github.com/jgm/peg-markdown
# [PHPE]: http://michelf.com/projects/php-markdown/extra/#def-list
# [syntax]: http://daringfireball.net/projects/markdown/syntax
#--
# Last updated to jgm/peg-markdown commit 8f8fc22ef0
class RDoc::Markdown
  # :stopdoc:

    # This is distinct from setup_parser so that a standalone parser
    # can redefine #initialize and still have access to the proper
    # parser setup code.
    def initialize(str, debug=false)
      setup_parser(str, debug)
    end



    # Prepares for parsing +str+.  If you define a custom initialize you must
    # call this method before #parse
    def setup_parser(str, debug=false)
      set_string str, 0
      @memoizations = Hash.new { |h,k| h[k] = {} }
      @result = nil
      @failed_rule = nil
      @failing_rule_offset = -1

      setup_foreign_grammar
    end

    attr_reader :string
    attr_reader :failing_rule_offset
    attr_accessor :result, :pos

    def current_column(target=pos)
      if c = string.rindex("\n", target-1)
        return target - c - 1
      end

      target + 1
    end

    def current_line(target=pos)
      cur_offset = 0
      cur_line = 0

      string.each_line do |line|
        cur_line += 1
        cur_offset += line.size
        return cur_line if cur_offset >= target
      end

      -1
    end

    def lines
      lines = []
      string.each_line { |l| lines << l }
      lines
    end



    def get_text(start)
      @string[start..@pos-1]
    end

    # Sets the string and current parsing position for the parser.
    def set_string string, pos
      @string = string
      @string_size = string ? string.size : 0
      @pos = pos
    end

    def show_pos
      width = 10
      if @pos < width
        "#{@pos} (\"#{@string[0,@pos]}\" @ \"#{@string[@pos,width]}\")"
      else
        "#{@pos} (\"... #{@string[@pos - width, width]}\" @ \"#{@string[@pos,width]}\")"
      end
    end

    def failure_info
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        "line #{l}, column #{c}: failed rule '#{info.name}' = '#{info.rendered}'"
      else
        "line #{l}, column #{c}: failed rule '#{@failed_rule}'"
      end
    end

    def failure_caret
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset

      line = lines[l-1]
      "#{line}\n#{' ' * (c - 1)}^"
    end

    def failure_character
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset
      lines[l-1][c-1, 1]
    end

    def failure_oneline
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset

      char = lines[l-1][c-1, 1]

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        "@#{l}:#{c} failed rule '#{info.name}', got '#{char}'"
      else
        "@#{l}:#{c} failed rule '#{@failed_rule}', got '#{char}'"
      end
    end

    class ParseError < RuntimeError
    end

    def raise_error
      raise ParseError, failure_oneline
    end

    def show_error(io=STDOUT)
      error_pos = @failing_rule_offset
      line_no = current_line(error_pos)
      col_no = current_column(error_pos)

      io.puts "On line #{line_no}, column #{col_no}:"

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        io.puts "Failed to match '#{info.rendered}' (rule '#{info.name}')"
      else
        io.puts "Failed to match rule '#{@failed_rule}'"
      end

      io.puts "Got: #{string[error_pos,1].inspect}"
      line = lines[line_no-1]
      io.puts "=> #{line}"
      io.print(" " * (col_no + 3))
      io.puts "^"
    end

    def set_failed_rule(name)
      if @pos > @failing_rule_offset
        @failed_rule = name
        @failing_rule_offset = @pos
      end
    end

    attr_reader :failed_rule

    def match_string(str)
      len = str.size
      if @string[pos,len] == str
        @pos += len
        return str
      end

      return nil
    end

    def scan(reg)
      if m = reg.match(@string, @pos)
        @pos = m.end(0)
        return true
      end

      return nil
    end

    if "".respond_to? :ord
      def get_byte
        if @pos >= @string_size
          return nil
        end

        s = @string[@pos].ord
        @pos += 1
        s
      end
    else
      def get_byte
        if @pos >= @string_size
          return nil
        end

        s = @string[@pos]
        @pos += 1
        s
      end
    end

    def parse(rule=nil)
      # We invoke the rules indirectly via apply
      # instead of by just calling them as methods because
      # if the rules use left recursion, apply needs to
      # manage that.

      if !rule
        apply(:_root)
      else
        method = rule.gsub("-","_hyphen_")
        apply :"_#{method}"
      end
    end

    class MemoEntry
      def initialize(ans, pos)
        @ans = ans
        @pos = pos
        @result = nil
        @set = false
        @left_rec = false
      end

      attr_reader :ans, :pos, :result, :set
      attr_accessor :left_rec

      def move!(ans, pos, result)
        @ans = ans
        @pos = pos
        @result = result
        @set = true
        @left_rec = false
      end
    end

    def external_invoke(other, rule, *args)
      old_pos = @pos
      old_string = @string

      set_string other.string, other.pos

      begin
        if val = __send__(rule, *args)
          other.pos = @pos
          other.result = @result
        else
          other.set_failed_rule "#{self.class}##{rule}"
        end
        val
      ensure
        set_string old_string, old_pos
      end
    end

    def apply_with_args(rule, *args)
      memo_key = [rule, args]
      if m = @memoizations[memo_key][@pos]
        @pos = m.pos
        if !m.set
          m.left_rec = true
          return nil
        end

        @result = m.result

        return m.ans
      else
        m = MemoEntry.new(nil, @pos)
        @memoizations[memo_key][@pos] = m
        start_pos = @pos

        ans = __send__ rule, *args

        lr = m.left_rec

        m.move! ans, @pos, @result

        # Don't bother trying to grow the left recursion
        # if it's failing straight away (thus there is no seed)
        if ans and lr
          return grow_lr(rule, args, start_pos, m)
        else
          return ans
        end
      end
    end

    def apply(rule)
      if m = @memoizations[rule][@pos]
        @pos = m.pos
        if !m.set
          m.left_rec = true
          return nil
        end

        @result = m.result

        return m.ans
      else
        m = MemoEntry.new(nil, @pos)
        @memoizations[rule][@pos] = m
        start_pos = @pos

        ans = __send__ rule

        lr = m.left_rec

        m.move! ans, @pos, @result

        # Don't bother trying to grow the left recursion
        # if it's failing straight away (thus there is no seed)
        if ans and lr
          return grow_lr(rule, nil, start_pos, m)
        else
          return ans
        end
      end
    end

    def grow_lr(rule, args, start_pos, m)
      while true
        @pos = start_pos
        @result = m.result

        if args
          ans = __send__ rule, *args
        else
          ans = __send__ rule
        end
        return nil unless ans

        break if @pos <= m.pos

        m.move! ans, @pos, @result
      end

      @result = m.result
      @pos = m.pos
      return m.ans
    end

    class RuleInfo
      def initialize(name, rendered)
        @name = name
        @rendered = rendered
      end

      attr_reader :name, :rendered
    end

    def self.rule_info(name, rendered)
      RuleInfo.new(name, rendered)
    end


  # :startdoc:



  require 'rdoc'
  require 'rdoc/markup/to_joined_paragraph'
  require 'rdoc/markdown/entities'

  require 'rdoc/markdown/literals'

  ##
  # Supported extensions

  EXTENSIONS = []

  ##
  # Extensions enabled by default

  DEFAULT_EXTENSIONS = [
    :definition_lists,
    :github,
    :html,
    :notes,
    :strike,
  ]

  # :section: Extensions

  ##
  # Creates extension methods for the `name` extension to enable and disable
  # the extension and to query if they are active.

  def self.extension name
    EXTENSIONS << name

    define_method "#{name}?" do
      extension? name
    end

    define_method "#{name}=" do |enable|
      extension name, enable
    end
  end

  ##
  # Converts all newlines into hard breaks

  extension :break_on_newline

  ##
  # Allow style blocks

  extension :css

  ##
  # Allow PHP Markdown Extras style definition lists

  extension :definition_lists

  ##
  # Allow Github Flavored Markdown

  extension :github

  ##
  # Allow HTML

  extension :html

  ##
  # Enables the notes extension

  extension :notes

  ##
  # Enables the strike extension

  extension :strike

  # :section:

  ##
  # Parses the `markdown` document into an RDoc::Document using the default
  # extensions.

  def self.parse markdown
    parser = new

    parser.parse markdown
  end

  # TODO remove when kpeg 0.10 is released
  alias orig_initialize initialize # :nodoc:

  ##
  # Creates a new markdown parser that enables the given +extensions+.

  def initialize extensions = DEFAULT_EXTENSIONS, debug = false
    @debug      = debug
    @formatter  = RDoc::Markup::ToJoinedParagraph.new
    @extensions = extensions

    @references          = nil
    @unlinked_references = nil

    @footnotes       = nil
    @note_order      = nil
  end

  ##
  # Wraps `text` in emphasis for rdoc inline formatting

  def emphasis text
    if text =~ /\A[a-z\d.\/]+\z/i then
      "_#{text}_"
    else
      "<em>#{text}</em>"
    end
  end

  ##
  # :category: Extensions
  #
  # Is the extension `name` enabled?

  def extension? name
    @extensions.include? name
  end

  ##
  # :category: Extensions
  #
  # Enables or disables the extension with `name`

  def extension name, enable
    if enable then
      @extensions |= [name]
    else
      @extensions -= [name]
    end
  end

  ##
  # Parses `text` in a clone of this parser.  This is used for handling nested
  # lists the same way as markdown_parser.

  def inner_parse text # :nodoc:
    parser = clone

    parser.setup_parser text, @debug

    parser.peg_parse

    doc = parser.result

    doc.accept @formatter

    doc.parts
  end

  ##
  # Finds a link reference for `label` and creates a new link to it with
  # `content` as the link text.  If `label` was not encountered in the
  # reference-gathering parser pass the label and content are reconstructed
  # with the linking `text` (usually whitespace).

  def link_to content, label = content, text = nil
    raise ParseError, 'enable notes extension' if
      content.start_with? '^' and label.equal? content

    if ref = @references[label] then
      "{#{content}}[#{ref}]"
    elsif label.equal? content then
      "[#{content}]#{text}"
    else
      "[#{content}]#{text}[#{label}]"
    end
  end

  ##
  # Creates an RDoc::Markup::ListItem by parsing the `unparsed` content from
  # the first parsing pass.

  def list_item_from unparsed
    parsed = inner_parse unparsed.join
    RDoc::Markup::ListItem.new nil, *parsed
  end

  ##
  # Stores `label` as a note and fills in previously unknown note references.

  def note label
    #foottext = "rdoc-label:foottext-#{label}:footmark-#{label}"

    #ref.replace foottext if ref = @unlinked_notes.delete(label)

    @notes[label] = foottext

    #"{^1}[rdoc-label:footmark-#{label}:foottext-#{label}] "
  end

  ##
  # Creates a new link for the footnote `reference` and adds the reference to
  # the note order list for proper display at the end of the document.

  def note_for ref
    @note_order << ref

    label = @note_order.length

    "{*#{label}}[rdoc-label:foottext-#{label}:footmark-#{label}]"
  end

  ##
  # The internal kpeg parse method

  alias peg_parse parse # :nodoc:

  ##
  # Creates an RDoc::Markup::Paragraph from `parts` and including
  # extension-specific behavior

  def paragraph parts
    parts = parts.map do |part|
      if "\n" == part then
        RDoc::Markup::HardBreak.new
      else
        part
      end
    end if break_on_newline?

    RDoc::Markup::Paragraph.new(*parts)
  end

  ##
  # Parses `markdown` into an RDoc::Document

  def parse markdown
    @references          = {}
    @unlinked_references = {}

    markdown += "\n\n"

    setup_parser markdown, @debug
    peg_parse 'References'

    if notes? then
      @footnotes       = {}

      setup_parser markdown, @debug
      peg_parse 'Notes'

      # using note_order on the first pass would be a bug
      @note_order      = []
    end

    setup_parser markdown, @debug
    peg_parse

    doc = result

    if notes? and not @footnotes.empty? then
      doc << RDoc::Markup::Rule.new(1)

      @note_order.each_with_index do |ref, index|
        label = index + 1
        note = @footnotes[ref]

        link = "{^#{label}}[rdoc-label:footmark-#{label}:foottext-#{label}] "
        note.parts.unshift link

        doc << note
      end
    end

    doc.accept @formatter

    doc
  end

  ##
  # Stores `label` as a reference to `link` and fills in previously unknown
  # link references.

  def reference label, link
    if ref = @unlinked_references.delete(label) then
      ref.replace link
    end

    @references[label] = link
  end

  ##
  # Wraps `text` in strong markup for rdoc inline formatting

  def strong text
    if text =~ /\A[a-z\d.\/-]+\z/i then
      "*#{text}*"
    else
      "<b>#{text}</b>"
    end
  end

  ##
  # Wraps `text` in strike markup for rdoc inline formatting

  def strike text
    if text =~ /\A[a-z\d.\/-]+\z/i then
      "~#{text}~"
    else
      "<s>#{text}</s>"
    end
  end


  # :stopdoc:
  def setup_foreign_grammar
    @_grammar_literals = RDoc::Markdown::Literals.new(nil)
  end

  # root = Doc
  def _root
    _tmp = apply(:_Doc)
    set_failed_rule :_root unless _tmp
    return _tmp
  end

  # Doc = BOM? Block*:a { RDoc::Markup::Document.new(*a.compact) }
  def _Doc

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = apply(:_BOM)
      unless _tmp
        _tmp = true
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      _ary = []
      while true
        _tmp = apply(:_Block)
        _ary << @result if _tmp
        break unless _tmp
      end
      _tmp = true
      @result = _ary
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::Document.new(*a.compact) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Doc unless _tmp
    return _tmp
  end

  # Block = @BlankLine* (BlockQuote | Verbatim | CodeFence | Table | Note | Reference | HorizontalRule | Heading | OrderedList | BulletList | DefinitionList | HtmlBlock | StyleBlock | Para | Plain)
  def _Block

    _save = self.pos
    while true # sequence
      while true
        _tmp = _BlankLine()
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end

      _save2 = self.pos
      while true # choice
        _tmp = apply(:_BlockQuote)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_Verbatim)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_CodeFence)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_Table)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_Note)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_Reference)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_HorizontalRule)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_Heading)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_OrderedList)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_BulletList)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_DefinitionList)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_HtmlBlock)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_StyleBlock)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_Para)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_Plain)
        break if _tmp
        self.pos = _save2
        break
      end # end choice

      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Block unless _tmp
    return _tmp
  end

  # Para = @NonindentSpace Inlines:a @BlankLine+ { paragraph a }
  def _Para

    _save = self.pos
    while true # sequence
      _tmp = _NonindentSpace()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Inlines)
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = _BlankLine()
      if _tmp
        while true
          _tmp = _BlankLine()
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  paragraph a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Para unless _tmp
    return _tmp
  end

  # Plain = Inlines:a { paragraph a }
  def _Plain

    _save = self.pos
    while true # sequence
      _tmp = apply(:_Inlines)
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  paragraph a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Plain unless _tmp
    return _tmp
  end

  # AtxInline = !@Newline !(@Sp /#*/ @Sp @Newline) Inline
  def _AtxInline

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = _Newline()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos

      _save3 = self.pos
      while true # sequence
        _tmp = _Sp()
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = scan(/\G(?-mix:#*)/)
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = _Sp()
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = _Newline()
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      _tmp = _tmp ? nil : true
      self.pos = _save2
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Inline)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_AtxInline unless _tmp
    return _tmp
  end

  # AtxStart = < /\#{1,6}/ > { text.length }
  def _AtxStart

    _save = self.pos
    while true # sequence
      _text_start = self.pos
      _tmp = scan(/\G(?-mix:\#{1,6})/)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text.length ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_AtxStart unless _tmp
    return _tmp
  end

  # AtxHeading = AtxStart:s @Sp AtxInline+:a (@Sp /#*/ @Sp)? @Newline { RDoc::Markup::Heading.new(s, a.join) }
  def _AtxHeading

    _save = self.pos
    while true # sequence
      _tmp = apply(:_AtxStart)
      s = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _ary = []
      _tmp = apply(:_AtxInline)
      if _tmp
        _ary << @result
        while true
          _tmp = apply(:_AtxInline)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save1
      end
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos

      _save3 = self.pos
      while true # sequence
        _tmp = _Sp()
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = scan(/\G(?-mix:#*)/)
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = _Sp()
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      unless _tmp
        _tmp = true
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::Heading.new(s, a.join) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_AtxHeading unless _tmp
    return _tmp
  end

  # SetextHeading = (SetextHeading1 | SetextHeading2)
  def _SetextHeading

    _save = self.pos
    while true # choice
      _tmp = apply(:_SetextHeading1)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_SetextHeading2)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_SetextHeading unless _tmp
    return _tmp
  end

  # SetextBottom1 = /={1,}/ @Newline
  def _SetextBottom1

    _save = self.pos
    while true # sequence
      _tmp = scan(/\G(?-mix:={1,})/)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_SetextBottom1 unless _tmp
    return _tmp
  end

  # SetextBottom2 = /-{1,}/ @Newline
  def _SetextBottom2

    _save = self.pos
    while true # sequence
      _tmp = scan(/\G(?-mix:-{1,})/)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_SetextBottom2 unless _tmp
    return _tmp
  end

  # SetextHeading1 = &(@RawLine SetextBottom1) @StartList:a (!@Endline Inline:b { a << b })+ @Sp @Newline SetextBottom1 { RDoc::Markup::Heading.new(1, a.join) }
  def _SetextHeading1

    _save = self.pos
    while true # sequence
      _save1 = self.pos

      _save2 = self.pos
      while true # sequence
        _tmp = _RawLine()
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_SetextBottom1)
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save3 = self.pos

      _save4 = self.pos
      while true # sequence
        _save5 = self.pos
        _tmp = _Endline()
        _tmp = _tmp ? nil : true
        self.pos = _save5
        unless _tmp
          self.pos = _save4
          break
        end
        _tmp = apply(:_Inline)
        b = @result
        unless _tmp
          self.pos = _save4
          break
        end
        @result = begin;  a << b ; end
        _tmp = true
        unless _tmp
          self.pos = _save4
        end
        break
      end # end sequence

      if _tmp
        while true

          _save6 = self.pos
          while true # sequence
            _save7 = self.pos
            _tmp = _Endline()
            _tmp = _tmp ? nil : true
            self.pos = _save7
            unless _tmp
              self.pos = _save6
              break
            end
            _tmp = apply(:_Inline)
            b = @result
            unless _tmp
              self.pos = _save6
              break
            end
            @result = begin;  a << b ; end
            _tmp = true
            unless _tmp
              self.pos = _save6
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save3
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_SetextBottom1)
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::Heading.new(1, a.join) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_SetextHeading1 unless _tmp
    return _tmp
  end

  # SetextHeading2 = &(@RawLine SetextBottom2) @StartList:a (!@Endline Inline:b { a << b })+ @Sp @Newline SetextBottom2 { RDoc::Markup::Heading.new(2, a.join) }
  def _SetextHeading2

    _save = self.pos
    while true # sequence
      _save1 = self.pos

      _save2 = self.pos
      while true # sequence
        _tmp = _RawLine()
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_SetextBottom2)
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save3 = self.pos

      _save4 = self.pos
      while true # sequence
        _save5 = self.pos
        _tmp = _Endline()
        _tmp = _tmp ? nil : true
        self.pos = _save5
        unless _tmp
          self.pos = _save4
          break
        end
        _tmp = apply(:_Inline)
        b = @result
        unless _tmp
          self.pos = _save4
          break
        end
        @result = begin;  a << b ; end
        _tmp = true
        unless _tmp
          self.pos = _save4
        end
        break
      end # end sequence

      if _tmp
        while true

          _save6 = self.pos
          while true # sequence
            _save7 = self.pos
            _tmp = _Endline()
            _tmp = _tmp ? nil : true
            self.pos = _save7
            unless _tmp
              self.pos = _save6
              break
            end
            _tmp = apply(:_Inline)
            b = @result
            unless _tmp
              self.pos = _save6
              break
            end
            @result = begin;  a << b ; end
            _tmp = true
            unless _tmp
              self.pos = _save6
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save3
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_SetextBottom2)
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::Heading.new(2, a.join) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_SetextHeading2 unless _tmp
    return _tmp
  end

  # Heading = (SetextHeading | AtxHeading)
  def _Heading

    _save = self.pos
    while true # choice
      _tmp = apply(:_SetextHeading)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_AtxHeading)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_Heading unless _tmp
    return _tmp
  end

  # BlockQuote = BlockQuoteRaw:a { RDoc::Markup::BlockQuote.new(*a) }
  def _BlockQuote

    _save = self.pos
    while true # sequence
      _tmp = apply(:_BlockQuoteRaw)
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::BlockQuote.new(*a) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_BlockQuote unless _tmp
    return _tmp
  end

  # BlockQuoteRaw = @StartList:a (">" " "? Line:l { a << l } (!">" !@BlankLine Line:c { a << c })* (@BlankLine:n { a << n })*)+ { inner_parse a.join }
  def _BlockQuoteRaw

    _save = self.pos
    while true # sequence
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos

      _save2 = self.pos
      while true # sequence
        _tmp = match_string(">")
        unless _tmp
          self.pos = _save2
          break
        end
        _save3 = self.pos
        _tmp = match_string(" ")
        unless _tmp
          _tmp = true
          self.pos = _save3
        end
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_Line)
        l = @result
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  a << l ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
          break
        end
        while true

          _save5 = self.pos
          while true # sequence
            _save6 = self.pos
            _tmp = match_string(">")
            _tmp = _tmp ? nil : true
            self.pos = _save6
            unless _tmp
              self.pos = _save5
              break
            end
            _save7 = self.pos
            _tmp = _BlankLine()
            _tmp = _tmp ? nil : true
            self.pos = _save7
            unless _tmp
              self.pos = _save5
              break
            end
            _tmp = apply(:_Line)
            c = @result
            unless _tmp
              self.pos = _save5
              break
            end
            @result = begin;  a << c ; end
            _tmp = true
            unless _tmp
              self.pos = _save5
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
        unless _tmp
          self.pos = _save2
          break
        end
        while true

          _save9 = self.pos
          while true # sequence
            _tmp = _BlankLine()
            n = @result
            unless _tmp
              self.pos = _save9
              break
            end
            @result = begin;  a << n ; end
            _tmp = true
            unless _tmp
              self.pos = _save9
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      if _tmp
        while true

          _save10 = self.pos
          while true # sequence
            _tmp = match_string(">")
            unless _tmp
              self.pos = _save10
              break
            end
            _save11 = self.pos
            _tmp = match_string(" ")
            unless _tmp
              _tmp = true
              self.pos = _save11
            end
            unless _tmp
              self.pos = _save10
              break
            end
            _tmp = apply(:_Line)
            l = @result
            unless _tmp
              self.pos = _save10
              break
            end
            @result = begin;  a << l ; end
            _tmp = true
            unless _tmp
              self.pos = _save10
              break
            end
            while true

              _save13 = self.pos
              while true # sequence
                _save14 = self.pos
                _tmp = match_string(">")
                _tmp = _tmp ? nil : true
                self.pos = _save14
                unless _tmp
                  self.pos = _save13
                  break
                end
                _save15 = self.pos
                _tmp = _BlankLine()
                _tmp = _tmp ? nil : true
                self.pos = _save15
                unless _tmp
                  self.pos = _save13
                  break
                end
                _tmp = apply(:_Line)
                c = @result
                unless _tmp
                  self.pos = _save13
                  break
                end
                @result = begin;  a << c ; end
                _tmp = true
                unless _tmp
                  self.pos = _save13
                end
                break
              end # end sequence

              break unless _tmp
            end
            _tmp = true
            unless _tmp
              self.pos = _save10
              break
            end
            while true

              _save17 = self.pos
              while true # sequence
                _tmp = _BlankLine()
                n = @result
                unless _tmp
                  self.pos = _save17
                  break
                end
                @result = begin;  a << n ; end
                _tmp = true
                unless _tmp
                  self.pos = _save17
                end
                break
              end # end sequence

              break unless _tmp
            end
            _tmp = true
            unless _tmp
              self.pos = _save10
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  inner_parse a.join ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_BlockQuoteRaw unless _tmp
    return _tmp
  end

  # NonblankIndentedLine = !@BlankLine IndentedLine
  def _NonblankIndentedLine

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = _BlankLine()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_IndentedLine)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_NonblankIndentedLine unless _tmp
    return _tmp
  end

  # VerbatimChunk = @BlankLine*:a NonblankIndentedLine+:b { a.concat b }
  def _VerbatimChunk

    _save = self.pos
    while true # sequence
      _ary = []
      while true
        _tmp = _BlankLine()
        _ary << @result if _tmp
        break unless _tmp
      end
      _tmp = true
      @result = _ary
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _ary = []
      _tmp = apply(:_NonblankIndentedLine)
      if _tmp
        _ary << @result
        while true
          _tmp = apply(:_NonblankIndentedLine)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save2
      end
      b = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a.concat b ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_VerbatimChunk unless _tmp
    return _tmp
  end

  # Verbatim = VerbatimChunk+:a { RDoc::Markup::Verbatim.new(*a.flatten) }
  def _Verbatim

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _ary = []
      _tmp = apply(:_VerbatimChunk)
      if _tmp
        _ary << @result
        while true
          _tmp = apply(:_VerbatimChunk)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save1
      end
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::Verbatim.new(*a.flatten) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Verbatim unless _tmp
    return _tmp
  end

  # HorizontalRule = @NonindentSpace ("*" @Sp "*" @Sp "*" (@Sp "*")* | "-" @Sp "-" @Sp "-" (@Sp "-")* | "_" @Sp "_" @Sp "_" (@Sp "_")*) @Sp @Newline @BlankLine+ { RDoc::Markup::Rule.new 1 }
  def _HorizontalRule

    _save = self.pos
    while true # sequence
      _tmp = _NonindentSpace()
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice

        _save2 = self.pos
        while true # sequence
          _tmp = match_string("*")
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = match_string("*")
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = match_string("*")
          unless _tmp
            self.pos = _save2
            break
          end
          while true

            _save4 = self.pos
            while true # sequence
              _tmp = _Sp()
              unless _tmp
                self.pos = _save4
                break
              end
              _tmp = match_string("*")
              unless _tmp
                self.pos = _save4
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1

        _save5 = self.pos
        while true # sequence
          _tmp = match_string("-")
          unless _tmp
            self.pos = _save5
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save5
            break
          end
          _tmp = match_string("-")
          unless _tmp
            self.pos = _save5
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save5
            break
          end
          _tmp = match_string("-")
          unless _tmp
            self.pos = _save5
            break
          end
          while true

            _save7 = self.pos
            while true # sequence
              _tmp = _Sp()
              unless _tmp
                self.pos = _save7
                break
              end
              _tmp = match_string("-")
              unless _tmp
                self.pos = _save7
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
          unless _tmp
            self.pos = _save5
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1

        _save8 = self.pos
        while true # sequence
          _tmp = match_string("_")
          unless _tmp
            self.pos = _save8
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save8
            break
          end
          _tmp = match_string("_")
          unless _tmp
            self.pos = _save8
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save8
            break
          end
          _tmp = match_string("_")
          unless _tmp
            self.pos = _save8
            break
          end
          while true

            _save10 = self.pos
            while true # sequence
              _tmp = _Sp()
              unless _tmp
                self.pos = _save10
                break
              end
              _tmp = match_string("_")
              unless _tmp
                self.pos = _save10
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
          unless _tmp
            self.pos = _save8
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
        break
      end
      _save11 = self.pos
      _tmp = _BlankLine()
      if _tmp
        while true
          _tmp = _BlankLine()
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save11
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::Rule.new 1 ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HorizontalRule unless _tmp
    return _tmp
  end

  # Bullet = !HorizontalRule @NonindentSpace /[+*-]/ @Spacechar+
  def _Bullet

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = apply(:_HorizontalRule)
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _NonindentSpace()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = scan(/\G(?-mix:[+*-])/)
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _tmp = _Spacechar()
      if _tmp
        while true
          _tmp = _Spacechar()
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Bullet unless _tmp
    return _tmp
  end

  # BulletList = &Bullet (ListTight | ListLoose):a { RDoc::Markup::List.new(:BULLET, *a) }
  def _BulletList

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = apply(:_Bullet)
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end

      _save2 = self.pos
      while true # choice
        _tmp = apply(:_ListTight)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_ListLoose)
        break if _tmp
        self.pos = _save2
        break
      end # end choice

      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::List.new(:BULLET, *a) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_BulletList unless _tmp
    return _tmp
  end

  # ListTight = ListItemTight+:a @BlankLine* !(Bullet | Enumerator) { a }
  def _ListTight

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _ary = []
      _tmp = apply(:_ListItemTight)
      if _tmp
        _ary << @result
        while true
          _tmp = apply(:_ListItemTight)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save1
      end
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = _BlankLine()
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _save3 = self.pos

      _save4 = self.pos
      while true # choice
        _tmp = apply(:_Bullet)
        break if _tmp
        self.pos = _save4
        _tmp = apply(:_Enumerator)
        break if _tmp
        self.pos = _save4
        break
      end # end choice

      _tmp = _tmp ? nil : true
      self.pos = _save3
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ListTight unless _tmp
    return _tmp
  end

  # ListLoose = @StartList:a (ListItem:b @BlankLine* { a << b })+ { a }
  def _ListLoose

    _save = self.pos
    while true # sequence
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos

      _save2 = self.pos
      while true # sequence
        _tmp = apply(:_ListItem)
        b = @result
        unless _tmp
          self.pos = _save2
          break
        end
        while true
          _tmp = _BlankLine()
          break unless _tmp
        end
        _tmp = true
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  a << b ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      if _tmp
        while true

          _save4 = self.pos
          while true # sequence
            _tmp = apply(:_ListItem)
            b = @result
            unless _tmp
              self.pos = _save4
              break
            end
            while true
              _tmp = _BlankLine()
              break unless _tmp
            end
            _tmp = true
            unless _tmp
              self.pos = _save4
              break
            end
            @result = begin;  a << b ; end
            _tmp = true
            unless _tmp
              self.pos = _save4
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ListLoose unless _tmp
    return _tmp
  end

  # ListItem = (Bullet | Enumerator) @StartList:a ListBlock:b { a << b } (ListContinuationBlock:c { a.push(*c) })* { list_item_from a }
  def _ListItem

    _save = self.pos
    while true # sequence

      _save1 = self.pos
      while true # choice
        _tmp = apply(:_Bullet)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_Enumerator)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_ListBlock)
      b = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a << b ; end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save3 = self.pos
        while true # sequence
          _tmp = apply(:_ListContinuationBlock)
          c = @result
          unless _tmp
            self.pos = _save3
            break
          end
          @result = begin;  a.push(*c) ; end
          _tmp = true
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  list_item_from a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ListItem unless _tmp
    return _tmp
  end

  # ListItemTight = (Bullet | Enumerator) ListBlock:a (!@BlankLine ListContinuationBlock:b { a.push(*b) })* !ListContinuationBlock { list_item_from a }
  def _ListItemTight

    _save = self.pos
    while true # sequence

      _save1 = self.pos
      while true # choice
        _tmp = apply(:_Bullet)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_Enumerator)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_ListBlock)
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save3 = self.pos
        while true # sequence
          _save4 = self.pos
          _tmp = _BlankLine()
          _tmp = _tmp ? nil : true
          self.pos = _save4
          unless _tmp
            self.pos = _save3
            break
          end
          _tmp = apply(:_ListContinuationBlock)
          b = @result
          unless _tmp
            self.pos = _save3
            break
          end
          @result = begin;  a.push(*b) ; end
          _tmp = true
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _save5 = self.pos
      _tmp = apply(:_ListContinuationBlock)
      _tmp = _tmp ? nil : true
      self.pos = _save5
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  list_item_from a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ListItemTight unless _tmp
    return _tmp
  end

  # ListBlock = !@BlankLine Line:a ListBlockLine*:c { [a, *c] }
  def _ListBlock

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = _BlankLine()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Line)
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _ary = []
      while true
        _tmp = apply(:_ListBlockLine)
        _ary << @result if _tmp
        break unless _tmp
      end
      _tmp = true
      @result = _ary
      c = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  [a, *c] ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ListBlock unless _tmp
    return _tmp
  end

  # ListContinuationBlock = @StartList:a @BlankLine* { a << "\n" } (Indent ListBlock:b { a.concat b })+ { a }
  def _ListContinuationBlock

    _save = self.pos
    while true # sequence
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = _BlankLine()
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a << "\n" ; end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos

      _save3 = self.pos
      while true # sequence
        _tmp = apply(:_Indent)
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = apply(:_ListBlock)
        b = @result
        unless _tmp
          self.pos = _save3
          break
        end
        @result = begin;  a.concat b ; end
        _tmp = true
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      if _tmp
        while true

          _save4 = self.pos
          while true # sequence
            _tmp = apply(:_Indent)
            unless _tmp
              self.pos = _save4
              break
            end
            _tmp = apply(:_ListBlock)
            b = @result
            unless _tmp
              self.pos = _save4
              break
            end
            @result = begin;  a.concat b ; end
            _tmp = true
            unless _tmp
              self.pos = _save4
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ListContinuationBlock unless _tmp
    return _tmp
  end

  # Enumerator = @NonindentSpace [0-9]+ "." @Spacechar+
  def _Enumerator

    _save = self.pos
    while true # sequence
      _tmp = _NonindentSpace()
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _save2 = self.pos
      _tmp = get_byte
      if _tmp
        unless _tmp >= 48 and _tmp <= 57
          self.pos = _save2
          _tmp = nil
        end
      end
      if _tmp
        while true
          _save3 = self.pos
          _tmp = get_byte
          if _tmp
            unless _tmp >= 48 and _tmp <= 57
              self.pos = _save3
              _tmp = nil
            end
          end
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(".")
      unless _tmp
        self.pos = _save
        break
      end
      _save4 = self.pos
      _tmp = _Spacechar()
      if _tmp
        while true
          _tmp = _Spacechar()
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save4
      end
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Enumerator unless _tmp
    return _tmp
  end

  # OrderedList = &Enumerator (ListTight | ListLoose):a { RDoc::Markup::List.new(:NUMBER, *a) }
  def _OrderedList

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = apply(:_Enumerator)
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end

      _save2 = self.pos
      while true # choice
        _tmp = apply(:_ListTight)
        break if _tmp
        self.pos = _save2
        _tmp = apply(:_ListLoose)
        break if _tmp
        self.pos = _save2
        break
      end # end choice

      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::List.new(:NUMBER, *a) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_OrderedList unless _tmp
    return _tmp
  end

  # ListBlockLine = !@BlankLine !(Indent? (Bullet | Enumerator)) !HorizontalRule OptionallyIndentedLine
  def _ListBlockLine

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = _BlankLine()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos

      _save3 = self.pos
      while true # sequence
        _save4 = self.pos
        _tmp = apply(:_Indent)
        unless _tmp
          _tmp = true
          self.pos = _save4
        end
        unless _tmp
          self.pos = _save3
          break
        end

        _save5 = self.pos
        while true # choice
          _tmp = apply(:_Bullet)
          break if _tmp
          self.pos = _save5
          _tmp = apply(:_Enumerator)
          break if _tmp
          self.pos = _save5
          break
        end # end choice

        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      _tmp = _tmp ? nil : true
      self.pos = _save2
      unless _tmp
        self.pos = _save
        break
      end
      _save6 = self.pos
      _tmp = apply(:_HorizontalRule)
      _tmp = _tmp ? nil : true
      self.pos = _save6
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_OptionallyIndentedLine)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ListBlockLine unless _tmp
    return _tmp
  end

  # HtmlOpenAnchor = "<" Spnl ("a" | "A") Spnl HtmlAttribute* ">"
  def _HtmlOpenAnchor

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("a")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("A")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlOpenAnchor unless _tmp
    return _tmp
  end

  # HtmlCloseAnchor = "<" Spnl "/" ("a" | "A") Spnl ">"
  def _HtmlCloseAnchor

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("a")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("A")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlCloseAnchor unless _tmp
    return _tmp
  end

  # HtmlAnchor = HtmlOpenAnchor (HtmlAnchor | !HtmlCloseAnchor .)* HtmlCloseAnchor
  def _HtmlAnchor

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlOpenAnchor)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlAnchor)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlCloseAnchor)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlCloseAnchor)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlAnchor unless _tmp
    return _tmp
  end

  # HtmlBlockOpenAddress = "<" Spnl ("address" | "ADDRESS") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenAddress

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("address")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("ADDRESS")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenAddress unless _tmp
    return _tmp
  end

  # HtmlBlockCloseAddress = "<" Spnl "/" ("address" | "ADDRESS") Spnl ">"
  def _HtmlBlockCloseAddress

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("address")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("ADDRESS")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseAddress unless _tmp
    return _tmp
  end

  # HtmlBlockAddress = HtmlBlockOpenAddress (HtmlBlockAddress | !HtmlBlockCloseAddress .)* HtmlBlockCloseAddress
  def _HtmlBlockAddress

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenAddress)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockAddress)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseAddress)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseAddress)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockAddress unless _tmp
    return _tmp
  end

  # HtmlBlockOpenBlockquote = "<" Spnl ("blockquote" | "BLOCKQUOTE") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenBlockquote

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("blockquote")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("BLOCKQUOTE")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenBlockquote unless _tmp
    return _tmp
  end

  # HtmlBlockCloseBlockquote = "<" Spnl "/" ("blockquote" | "BLOCKQUOTE") Spnl ">"
  def _HtmlBlockCloseBlockquote

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("blockquote")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("BLOCKQUOTE")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseBlockquote unless _tmp
    return _tmp
  end

  # HtmlBlockBlockquote = HtmlBlockOpenBlockquote (HtmlBlockBlockquote | !HtmlBlockCloseBlockquote .)* HtmlBlockCloseBlockquote
  def _HtmlBlockBlockquote

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenBlockquote)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockBlockquote)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseBlockquote)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseBlockquote)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockBlockquote unless _tmp
    return _tmp
  end

  # HtmlBlockOpenCenter = "<" Spnl ("center" | "CENTER") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenCenter

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("center")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("CENTER")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenCenter unless _tmp
    return _tmp
  end

  # HtmlBlockCloseCenter = "<" Spnl "/" ("center" | "CENTER") Spnl ">"
  def _HtmlBlockCloseCenter

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("center")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("CENTER")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseCenter unless _tmp
    return _tmp
  end

  # HtmlBlockCenter = HtmlBlockOpenCenter (HtmlBlockCenter | !HtmlBlockCloseCenter .)* HtmlBlockCloseCenter
  def _HtmlBlockCenter

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenCenter)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockCenter)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseCenter)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseCenter)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCenter unless _tmp
    return _tmp
  end

  # HtmlBlockOpenDir = "<" Spnl ("dir" | "DIR") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenDir

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("dir")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("DIR")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenDir unless _tmp
    return _tmp
  end

  # HtmlBlockCloseDir = "<" Spnl "/" ("dir" | "DIR") Spnl ">"
  def _HtmlBlockCloseDir

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("dir")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("DIR")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseDir unless _tmp
    return _tmp
  end

  # HtmlBlockDir = HtmlBlockOpenDir (HtmlBlockDir | !HtmlBlockCloseDir .)* HtmlBlockCloseDir
  def _HtmlBlockDir

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenDir)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockDir)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseDir)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseDir)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockDir unless _tmp
    return _tmp
  end

  # HtmlBlockOpenDiv = "<" Spnl ("div" | "DIV") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenDiv

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("div")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("DIV")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenDiv unless _tmp
    return _tmp
  end

  # HtmlBlockCloseDiv = "<" Spnl "/" ("div" | "DIV") Spnl ">"
  def _HtmlBlockCloseDiv

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("div")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("DIV")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseDiv unless _tmp
    return _tmp
  end

  # HtmlBlockDiv = HtmlBlockOpenDiv (HtmlBlockDiv | !HtmlBlockCloseDiv .)* HtmlBlockCloseDiv
  def _HtmlBlockDiv

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenDiv)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockDiv)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseDiv)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseDiv)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockDiv unless _tmp
    return _tmp
  end

  # HtmlBlockOpenDl = "<" Spnl ("dl" | "DL") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenDl

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("dl")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("DL")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenDl unless _tmp
    return _tmp
  end

  # HtmlBlockCloseDl = "<" Spnl "/" ("dl" | "DL") Spnl ">"
  def _HtmlBlockCloseDl

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("dl")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("DL")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseDl unless _tmp
    return _tmp
  end

  # HtmlBlockDl = HtmlBlockOpenDl (HtmlBlockDl | !HtmlBlockCloseDl .)* HtmlBlockCloseDl
  def _HtmlBlockDl

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenDl)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockDl)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseDl)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseDl)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockDl unless _tmp
    return _tmp
  end

  # HtmlBlockOpenFieldset = "<" Spnl ("fieldset" | "FIELDSET") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenFieldset

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("fieldset")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("FIELDSET")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenFieldset unless _tmp
    return _tmp
  end

  # HtmlBlockCloseFieldset = "<" Spnl "/" ("fieldset" | "FIELDSET") Spnl ">"
  def _HtmlBlockCloseFieldset

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("fieldset")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("FIELDSET")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseFieldset unless _tmp
    return _tmp
  end

  # HtmlBlockFieldset = HtmlBlockOpenFieldset (HtmlBlockFieldset | !HtmlBlockCloseFieldset .)* HtmlBlockCloseFieldset
  def _HtmlBlockFieldset

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenFieldset)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockFieldset)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseFieldset)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseFieldset)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockFieldset unless _tmp
    return _tmp
  end

  # HtmlBlockOpenForm = "<" Spnl ("form" | "FORM") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenForm

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("form")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("FORM")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenForm unless _tmp
    return _tmp
  end

  # HtmlBlockCloseForm = "<" Spnl "/" ("form" | "FORM") Spnl ">"
  def _HtmlBlockCloseForm

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("form")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("FORM")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseForm unless _tmp
    return _tmp
  end

  # HtmlBlockForm = HtmlBlockOpenForm (HtmlBlockForm | !HtmlBlockCloseForm .)* HtmlBlockCloseForm
  def _HtmlBlockForm

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenForm)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockForm)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseForm)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseForm)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockForm unless _tmp
    return _tmp
  end

  # HtmlBlockOpenH1 = "<" Spnl ("h1" | "H1") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenH1

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h1")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H1")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenH1 unless _tmp
    return _tmp
  end

  # HtmlBlockCloseH1 = "<" Spnl "/" ("h1" | "H1") Spnl ">"
  def _HtmlBlockCloseH1

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h1")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H1")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseH1 unless _tmp
    return _tmp
  end

  # HtmlBlockH1 = HtmlBlockOpenH1 (HtmlBlockH1 | !HtmlBlockCloseH1 .)* HtmlBlockCloseH1
  def _HtmlBlockH1

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenH1)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockH1)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseH1)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseH1)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockH1 unless _tmp
    return _tmp
  end

  # HtmlBlockOpenH2 = "<" Spnl ("h2" | "H2") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenH2

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h2")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H2")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenH2 unless _tmp
    return _tmp
  end

  # HtmlBlockCloseH2 = "<" Spnl "/" ("h2" | "H2") Spnl ">"
  def _HtmlBlockCloseH2

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h2")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H2")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseH2 unless _tmp
    return _tmp
  end

  # HtmlBlockH2 = HtmlBlockOpenH2 (HtmlBlockH2 | !HtmlBlockCloseH2 .)* HtmlBlockCloseH2
  def _HtmlBlockH2

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenH2)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockH2)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseH2)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseH2)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockH2 unless _tmp
    return _tmp
  end

  # HtmlBlockOpenH3 = "<" Spnl ("h3" | "H3") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenH3

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h3")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H3")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenH3 unless _tmp
    return _tmp
  end

  # HtmlBlockCloseH3 = "<" Spnl "/" ("h3" | "H3") Spnl ">"
  def _HtmlBlockCloseH3

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h3")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H3")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseH3 unless _tmp
    return _tmp
  end

  # HtmlBlockH3 = HtmlBlockOpenH3 (HtmlBlockH3 | !HtmlBlockCloseH3 .)* HtmlBlockCloseH3
  def _HtmlBlockH3

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenH3)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockH3)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseH3)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseH3)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockH3 unless _tmp
    return _tmp
  end

  # HtmlBlockOpenH4 = "<" Spnl ("h4" | "H4") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenH4

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h4")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H4")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenH4 unless _tmp
    return _tmp
  end

  # HtmlBlockCloseH4 = "<" Spnl "/" ("h4" | "H4") Spnl ">"
  def _HtmlBlockCloseH4

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h4")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H4")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseH4 unless _tmp
    return _tmp
  end

  # HtmlBlockH4 = HtmlBlockOpenH4 (HtmlBlockH4 | !HtmlBlockCloseH4 .)* HtmlBlockCloseH4
  def _HtmlBlockH4

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenH4)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockH4)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseH4)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseH4)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockH4 unless _tmp
    return _tmp
  end

  # HtmlBlockOpenH5 = "<" Spnl ("h5" | "H5") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenH5

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h5")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H5")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenH5 unless _tmp
    return _tmp
  end

  # HtmlBlockCloseH5 = "<" Spnl "/" ("h5" | "H5") Spnl ">"
  def _HtmlBlockCloseH5

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h5")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H5")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseH5 unless _tmp
    return _tmp
  end

  # HtmlBlockH5 = HtmlBlockOpenH5 (HtmlBlockH5 | !HtmlBlockCloseH5 .)* HtmlBlockCloseH5
  def _HtmlBlockH5

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenH5)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockH5)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseH5)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseH5)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockH5 unless _tmp
    return _tmp
  end

  # HtmlBlockOpenH6 = "<" Spnl ("h6" | "H6") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenH6

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h6")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H6")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenH6 unless _tmp
    return _tmp
  end

  # HtmlBlockCloseH6 = "<" Spnl "/" ("h6" | "H6") Spnl ">"
  def _HtmlBlockCloseH6

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("h6")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("H6")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseH6 unless _tmp
    return _tmp
  end

  # HtmlBlockH6 = HtmlBlockOpenH6 (HtmlBlockH6 | !HtmlBlockCloseH6 .)* HtmlBlockCloseH6
  def _HtmlBlockH6

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenH6)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockH6)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseH6)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseH6)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockH6 unless _tmp
    return _tmp
  end

  # HtmlBlockOpenMenu = "<" Spnl ("menu" | "MENU") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenMenu

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("menu")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("MENU")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenMenu unless _tmp
    return _tmp
  end

  # HtmlBlockCloseMenu = "<" Spnl "/" ("menu" | "MENU") Spnl ">"
  def _HtmlBlockCloseMenu

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("menu")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("MENU")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseMenu unless _tmp
    return _tmp
  end

  # HtmlBlockMenu = HtmlBlockOpenMenu (HtmlBlockMenu | !HtmlBlockCloseMenu .)* HtmlBlockCloseMenu
  def _HtmlBlockMenu

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenMenu)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockMenu)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseMenu)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseMenu)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockMenu unless _tmp
    return _tmp
  end

  # HtmlBlockOpenNoframes = "<" Spnl ("noframes" | "NOFRAMES") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenNoframes

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("noframes")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("NOFRAMES")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenNoframes unless _tmp
    return _tmp
  end

  # HtmlBlockCloseNoframes = "<" Spnl "/" ("noframes" | "NOFRAMES") Spnl ">"
  def _HtmlBlockCloseNoframes

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("noframes")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("NOFRAMES")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseNoframes unless _tmp
    return _tmp
  end

  # HtmlBlockNoframes = HtmlBlockOpenNoframes (HtmlBlockNoframes | !HtmlBlockCloseNoframes .)* HtmlBlockCloseNoframes
  def _HtmlBlockNoframes

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenNoframes)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockNoframes)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseNoframes)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseNoframes)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockNoframes unless _tmp
    return _tmp
  end

  # HtmlBlockOpenNoscript = "<" Spnl ("noscript" | "NOSCRIPT") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenNoscript

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("noscript")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("NOSCRIPT")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenNoscript unless _tmp
    return _tmp
  end

  # HtmlBlockCloseNoscript = "<" Spnl "/" ("noscript" | "NOSCRIPT") Spnl ">"
  def _HtmlBlockCloseNoscript

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("noscript")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("NOSCRIPT")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseNoscript unless _tmp
    return _tmp
  end

  # HtmlBlockNoscript = HtmlBlockOpenNoscript (HtmlBlockNoscript | !HtmlBlockCloseNoscript .)* HtmlBlockCloseNoscript
  def _HtmlBlockNoscript

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenNoscript)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockNoscript)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseNoscript)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseNoscript)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockNoscript unless _tmp
    return _tmp
  end

  # HtmlBlockOpenOl = "<" Spnl ("ol" | "OL") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenOl

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("ol")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("OL")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenOl unless _tmp
    return _tmp
  end

  # HtmlBlockCloseOl = "<" Spnl "/" ("ol" | "OL") Spnl ">"
  def _HtmlBlockCloseOl

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("ol")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("OL")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseOl unless _tmp
    return _tmp
  end

  # HtmlBlockOl = HtmlBlockOpenOl (HtmlBlockOl | !HtmlBlockCloseOl .)* HtmlBlockCloseOl
  def _HtmlBlockOl

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenOl)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockOl)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseOl)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseOl)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOl unless _tmp
    return _tmp
  end

  # HtmlBlockOpenP = "<" Spnl ("p" | "P") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenP

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("p")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("P")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenP unless _tmp
    return _tmp
  end

  # HtmlBlockCloseP = "<" Spnl "/" ("p" | "P") Spnl ">"
  def _HtmlBlockCloseP

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("p")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("P")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseP unless _tmp
    return _tmp
  end

  # HtmlBlockP = HtmlBlockOpenP (HtmlBlockP | !HtmlBlockCloseP .)* HtmlBlockCloseP
  def _HtmlBlockP

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenP)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockP)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseP)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseP)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockP unless _tmp
    return _tmp
  end

  # HtmlBlockOpenPre = "<" Spnl ("pre" | "PRE") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenPre

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("pre")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("PRE")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenPre unless _tmp
    return _tmp
  end

  # HtmlBlockClosePre = "<" Spnl "/" ("pre" | "PRE") Spnl ">"
  def _HtmlBlockClosePre

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("pre")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("PRE")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockClosePre unless _tmp
    return _tmp
  end

  # HtmlBlockPre = HtmlBlockOpenPre (HtmlBlockPre | !HtmlBlockClosePre .)* HtmlBlockClosePre
  def _HtmlBlockPre

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenPre)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockPre)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockClosePre)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockClosePre)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockPre unless _tmp
    return _tmp
  end

  # HtmlBlockOpenTable = "<" Spnl ("table" | "TABLE") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenTable

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("table")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TABLE")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenTable unless _tmp
    return _tmp
  end

  # HtmlBlockCloseTable = "<" Spnl "/" ("table" | "TABLE") Spnl ">"
  def _HtmlBlockCloseTable

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("table")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TABLE")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseTable unless _tmp
    return _tmp
  end

  # HtmlBlockTable = HtmlBlockOpenTable (HtmlBlockTable | !HtmlBlockCloseTable .)* HtmlBlockCloseTable
  def _HtmlBlockTable

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenTable)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockTable)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseTable)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseTable)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockTable unless _tmp
    return _tmp
  end

  # HtmlBlockOpenUl = "<" Spnl ("ul" | "UL") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenUl

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("ul")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("UL")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenUl unless _tmp
    return _tmp
  end

  # HtmlBlockCloseUl = "<" Spnl "/" ("ul" | "UL") Spnl ">"
  def _HtmlBlockCloseUl

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("ul")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("UL")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseUl unless _tmp
    return _tmp
  end

  # HtmlBlockUl = HtmlBlockOpenUl (HtmlBlockUl | !HtmlBlockCloseUl .)* HtmlBlockCloseUl
  def _HtmlBlockUl

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenUl)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockUl)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseUl)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseUl)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockUl unless _tmp
    return _tmp
  end

  # HtmlBlockOpenDd = "<" Spnl ("dd" | "DD") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenDd

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("dd")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("DD")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenDd unless _tmp
    return _tmp
  end

  # HtmlBlockCloseDd = "<" Spnl "/" ("dd" | "DD") Spnl ">"
  def _HtmlBlockCloseDd

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("dd")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("DD")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseDd unless _tmp
    return _tmp
  end

  # HtmlBlockDd = HtmlBlockOpenDd (HtmlBlockDd | !HtmlBlockCloseDd .)* HtmlBlockCloseDd
  def _HtmlBlockDd

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenDd)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockDd)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseDd)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseDd)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockDd unless _tmp
    return _tmp
  end

  # HtmlBlockOpenDt = "<" Spnl ("dt" | "DT") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenDt

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("dt")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("DT")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenDt unless _tmp
    return _tmp
  end

  # HtmlBlockCloseDt = "<" Spnl "/" ("dt" | "DT") Spnl ">"
  def _HtmlBlockCloseDt

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("dt")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("DT")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseDt unless _tmp
    return _tmp
  end

  # HtmlBlockDt = HtmlBlockOpenDt (HtmlBlockDt | !HtmlBlockCloseDt .)* HtmlBlockCloseDt
  def _HtmlBlockDt

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenDt)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockDt)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseDt)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseDt)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockDt unless _tmp
    return _tmp
  end

  # HtmlBlockOpenFrameset = "<" Spnl ("frameset" | "FRAMESET") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenFrameset

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("frameset")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("FRAMESET")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenFrameset unless _tmp
    return _tmp
  end

  # HtmlBlockCloseFrameset = "<" Spnl "/" ("frameset" | "FRAMESET") Spnl ">"
  def _HtmlBlockCloseFrameset

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("frameset")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("FRAMESET")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseFrameset unless _tmp
    return _tmp
  end

  # HtmlBlockFrameset = HtmlBlockOpenFrameset (HtmlBlockFrameset | !HtmlBlockCloseFrameset .)* HtmlBlockCloseFrameset
  def _HtmlBlockFrameset

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenFrameset)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockFrameset)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseFrameset)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseFrameset)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockFrameset unless _tmp
    return _tmp
  end

  # HtmlBlockOpenLi = "<" Spnl ("li" | "LI") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenLi

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("li")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("LI")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenLi unless _tmp
    return _tmp
  end

  # HtmlBlockCloseLi = "<" Spnl "/" ("li" | "LI") Spnl ">"
  def _HtmlBlockCloseLi

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("li")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("LI")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseLi unless _tmp
    return _tmp
  end

  # HtmlBlockLi = HtmlBlockOpenLi (HtmlBlockLi | !HtmlBlockCloseLi .)* HtmlBlockCloseLi
  def _HtmlBlockLi

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenLi)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockLi)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseLi)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseLi)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockLi unless _tmp
    return _tmp
  end

  # HtmlBlockOpenTbody = "<" Spnl ("tbody" | "TBODY") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenTbody

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("tbody")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TBODY")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenTbody unless _tmp
    return _tmp
  end

  # HtmlBlockCloseTbody = "<" Spnl "/" ("tbody" | "TBODY") Spnl ">"
  def _HtmlBlockCloseTbody

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("tbody")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TBODY")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseTbody unless _tmp
    return _tmp
  end

  # HtmlBlockTbody = HtmlBlockOpenTbody (HtmlBlockTbody | !HtmlBlockCloseTbody .)* HtmlBlockCloseTbody
  def _HtmlBlockTbody

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenTbody)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockTbody)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseTbody)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseTbody)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockTbody unless _tmp
    return _tmp
  end

  # HtmlBlockOpenTd = "<" Spnl ("td" | "TD") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenTd

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("td")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TD")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenTd unless _tmp
    return _tmp
  end

  # HtmlBlockCloseTd = "<" Spnl "/" ("td" | "TD") Spnl ">"
  def _HtmlBlockCloseTd

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("td")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TD")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseTd unless _tmp
    return _tmp
  end

  # HtmlBlockTd = HtmlBlockOpenTd (HtmlBlockTd | !HtmlBlockCloseTd .)* HtmlBlockCloseTd
  def _HtmlBlockTd

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenTd)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockTd)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseTd)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseTd)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockTd unless _tmp
    return _tmp
  end

  # HtmlBlockOpenTfoot = "<" Spnl ("tfoot" | "TFOOT") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenTfoot

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("tfoot")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TFOOT")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenTfoot unless _tmp
    return _tmp
  end

  # HtmlBlockCloseTfoot = "<" Spnl "/" ("tfoot" | "TFOOT") Spnl ">"
  def _HtmlBlockCloseTfoot

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("tfoot")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TFOOT")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseTfoot unless _tmp
    return _tmp
  end

  # HtmlBlockTfoot = HtmlBlockOpenTfoot (HtmlBlockTfoot | !HtmlBlockCloseTfoot .)* HtmlBlockCloseTfoot
  def _HtmlBlockTfoot

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenTfoot)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockTfoot)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseTfoot)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseTfoot)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockTfoot unless _tmp
    return _tmp
  end

  # HtmlBlockOpenTh = "<" Spnl ("th" | "TH") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenTh

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("th")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TH")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenTh unless _tmp
    return _tmp
  end

  # HtmlBlockCloseTh = "<" Spnl "/" ("th" | "TH") Spnl ">"
  def _HtmlBlockCloseTh

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("th")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TH")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseTh unless _tmp
    return _tmp
  end

  # HtmlBlockTh = HtmlBlockOpenTh (HtmlBlockTh | !HtmlBlockCloseTh .)* HtmlBlockCloseTh
  def _HtmlBlockTh

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenTh)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockTh)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseTh)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseTh)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockTh unless _tmp
    return _tmp
  end

  # HtmlBlockOpenThead = "<" Spnl ("thead" | "THEAD") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenThead

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("thead")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("THEAD")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenThead unless _tmp
    return _tmp
  end

  # HtmlBlockCloseThead = "<" Spnl "/" ("thead" | "THEAD") Spnl ">"
  def _HtmlBlockCloseThead

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("thead")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("THEAD")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseThead unless _tmp
    return _tmp
  end

  # HtmlBlockThead = HtmlBlockOpenThead (HtmlBlockThead | !HtmlBlockCloseThead .)* HtmlBlockCloseThead
  def _HtmlBlockThead

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenThead)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockThead)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseThead)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseThead)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockThead unless _tmp
    return _tmp
  end

  # HtmlBlockOpenTr = "<" Spnl ("tr" | "TR") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenTr

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("tr")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TR")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenTr unless _tmp
    return _tmp
  end

  # HtmlBlockCloseTr = "<" Spnl "/" ("tr" | "TR") Spnl ">"
  def _HtmlBlockCloseTr

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("tr")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("TR")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseTr unless _tmp
    return _tmp
  end

  # HtmlBlockTr = HtmlBlockOpenTr (HtmlBlockTr | !HtmlBlockCloseTr .)* HtmlBlockCloseTr
  def _HtmlBlockTr

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenTr)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # choice
          _tmp = apply(:_HtmlBlockTr)
          break if _tmp
          self.pos = _save2

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = apply(:_HtmlBlockCloseTr)
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break if _tmp
          self.pos = _save2
          break
        end # end choice

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseTr)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockTr unless _tmp
    return _tmp
  end

  # HtmlBlockOpenScript = "<" Spnl ("script" | "SCRIPT") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenScript

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("script")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("SCRIPT")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenScript unless _tmp
    return _tmp
  end

  # HtmlBlockCloseScript = "<" Spnl "/" ("script" | "SCRIPT") Spnl ">"
  def _HtmlBlockCloseScript

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("script")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("SCRIPT")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseScript unless _tmp
    return _tmp
  end

  # HtmlBlockScript = HtmlBlockOpenScript (!HtmlBlockCloseScript .)* HtmlBlockCloseScript
  def _HtmlBlockScript

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenScript)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos
          _tmp = apply(:_HtmlBlockCloseScript)
          _tmp = _tmp ? nil : true
          self.pos = _save3
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseScript)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockScript unless _tmp
    return _tmp
  end

  # HtmlBlockOpenHead = "<" Spnl ("head" | "HEAD") Spnl HtmlAttribute* ">"
  def _HtmlBlockOpenHead

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("head")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("HEAD")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockOpenHead unless _tmp
    return _tmp
  end

  # HtmlBlockCloseHead = "<" Spnl "/" ("head" | "HEAD") Spnl ">"
  def _HtmlBlockCloseHead

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("head")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("HEAD")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockCloseHead unless _tmp
    return _tmp
  end

  # HtmlBlockHead = HtmlBlockOpenHead (!HtmlBlockCloseHead .)* HtmlBlockCloseHead
  def _HtmlBlockHead

    _save = self.pos
    while true # sequence
      _tmp = apply(:_HtmlBlockOpenHead)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos
          _tmp = apply(:_HtmlBlockCloseHead)
          _tmp = _tmp ? nil : true
          self.pos = _save3
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockCloseHead)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockHead unless _tmp
    return _tmp
  end

  # HtmlBlockInTags = (HtmlAnchor | HtmlBlockAddress | HtmlBlockBlockquote | HtmlBlockCenter | HtmlBlockDir | HtmlBlockDiv | HtmlBlockDl | HtmlBlockFieldset | HtmlBlockForm | HtmlBlockH1 | HtmlBlockH2 | HtmlBlockH3 | HtmlBlockH4 | HtmlBlockH5 | HtmlBlockH6 | HtmlBlockMenu | HtmlBlockNoframes | HtmlBlockNoscript | HtmlBlockOl | HtmlBlockP | HtmlBlockPre | HtmlBlockTable | HtmlBlockUl | HtmlBlockDd | HtmlBlockDt | HtmlBlockFrameset | HtmlBlockLi | HtmlBlockTbody | HtmlBlockTd | HtmlBlockTfoot | HtmlBlockTh | HtmlBlockThead | HtmlBlockTr | HtmlBlockScript | HtmlBlockHead)
  def _HtmlBlockInTags

    _save = self.pos
    while true # choice
      _tmp = apply(:_HtmlAnchor)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockAddress)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockBlockquote)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockCenter)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockDir)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockDiv)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockDl)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockFieldset)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockForm)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockH1)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockH2)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockH3)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockH4)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockH5)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockH6)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockMenu)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockNoframes)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockNoscript)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockOl)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockP)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockPre)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockTable)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockUl)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockDd)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockDt)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockFrameset)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockLi)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockTbody)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockTd)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockTfoot)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockTh)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockThead)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockTr)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockScript)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_HtmlBlockHead)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_HtmlBlockInTags unless _tmp
    return _tmp
  end

  # HtmlBlock = < (HtmlBlockInTags | HtmlComment | HtmlBlockSelfClosing | HtmlUnclosed) > @BlankLine+ { if html? then                 RDoc::Markup::Raw.new text               end }
  def _HtmlBlock

    _save = self.pos
    while true # sequence
      _text_start = self.pos

      _save1 = self.pos
      while true # choice
        _tmp = apply(:_HtmlBlockInTags)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_HtmlComment)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_HtmlBlockSelfClosing)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_HtmlUnclosed)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _tmp = _BlankLine()
      if _tmp
        while true
          _tmp = _BlankLine()
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  if html? then
                RDoc::Markup::Raw.new text
              end ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlock unless _tmp
    return _tmp
  end

  # HtmlUnclosed = "<" Spnl HtmlUnclosedType Spnl HtmlAttribute* Spnl ">"
  def _HtmlUnclosed

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlUnclosedType)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlUnclosed unless _tmp
    return _tmp
  end

  # HtmlUnclosedType = ("HR" | "hr")
  def _HtmlUnclosedType

    _save = self.pos
    while true # choice
      _tmp = match_string("HR")
      break if _tmp
      self.pos = _save
      _tmp = match_string("hr")
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_HtmlUnclosedType unless _tmp
    return _tmp
  end

  # HtmlBlockSelfClosing = "<" Spnl HtmlBlockType Spnl HtmlAttribute* "/" Spnl ">"
  def _HtmlBlockSelfClosing

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_HtmlBlockType)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlBlockSelfClosing unless _tmp
    return _tmp
  end

  # HtmlBlockType = ("ADDRESS" | "BLOCKQUOTE" | "CENTER" | "DD" | "DIR" | "DIV" | "DL" | "DT" | "FIELDSET" | "FORM" | "FRAMESET" | "H1" | "H2" | "H3" | "H4" | "H5" | "H6" | "HR" | "ISINDEX" | "LI" | "MENU" | "NOFRAMES" | "NOSCRIPT" | "OL" | "P" | "PRE" | "SCRIPT" | "TABLE" | "TBODY" | "TD" | "TFOOT" | "TH" | "THEAD" | "TR" | "UL" | "address" | "blockquote" | "center" | "dd" | "dir" | "div" | "dl" | "dt" | "fieldset" | "form" | "frameset" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "hr" | "isindex" | "li" | "menu" | "noframes" | "noscript" | "ol" | "p" | "pre" | "script" | "table" | "tbody" | "td" | "tfoot" | "th" | "thead" | "tr" | "ul")
  def _HtmlBlockType

    _save = self.pos
    while true # choice
      _tmp = match_string("ADDRESS")
      break if _tmp
      self.pos = _save
      _tmp = match_string("BLOCKQUOTE")
      break if _tmp
      self.pos = _save
      _tmp = match_string("CENTER")
      break if _tmp
      self.pos = _save
      _tmp = match_string("DD")
      break if _tmp
      self.pos = _save
      _tmp = match_string("DIR")
      break if _tmp
      self.pos = _save
      _tmp = match_string("DIV")
      break if _tmp
      self.pos = _save
      _tmp = match_string("DL")
      break if _tmp
      self.pos = _save
      _tmp = match_string("DT")
      break if _tmp
      self.pos = _save
      _tmp = match_string("FIELDSET")
      break if _tmp
      self.pos = _save
      _tmp = match_string("FORM")
      break if _tmp
      self.pos = _save
      _tmp = match_string("FRAMESET")
      break if _tmp
      self.pos = _save
      _tmp = match_string("H1")
      break if _tmp
      self.pos = _save
      _tmp = match_string("H2")
      break if _tmp
      self.pos = _save
      _tmp = match_string("H3")
      break if _tmp
      self.pos = _save
      _tmp = match_string("H4")
      break if _tmp
      self.pos = _save
      _tmp = match_string("H5")
      break if _tmp
      self.pos = _save
      _tmp = match_string("H6")
      break if _tmp
      self.pos = _save
      _tmp = match_string("HR")
      break if _tmp
      self.pos = _save
      _tmp = match_string("ISINDEX")
      break if _tmp
      self.pos = _save
      _tmp = match_string("LI")
      break if _tmp
      self.pos = _save
      _tmp = match_string("MENU")
      break if _tmp
      self.pos = _save
      _tmp = match_string("NOFRAMES")
      break if _tmp
      self.pos = _save
      _tmp = match_string("NOSCRIPT")
      break if _tmp
      self.pos = _save
      _tmp = match_string("OL")
      break if _tmp
      self.pos = _save
      _tmp = match_string("P")
      break if _tmp
      self.pos = _save
      _tmp = match_string("PRE")
      break if _tmp
      self.pos = _save
      _tmp = match_string("SCRIPT")
      break if _tmp
      self.pos = _save
      _tmp = match_string("TABLE")
      break if _tmp
      self.pos = _save
      _tmp = match_string("TBODY")
      break if _tmp
      self.pos = _save
      _tmp = match_string("TD")
      break if _tmp
      self.pos = _save
      _tmp = match_string("TFOOT")
      break if _tmp
      self.pos = _save
      _tmp = match_string("TH")
      break if _tmp
      self.pos = _save
      _tmp = match_string("THEAD")
      break if _tmp
      self.pos = _save
      _tmp = match_string("TR")
      break if _tmp
      self.pos = _save
      _tmp = match_string("UL")
      break if _tmp
      self.pos = _save
      _tmp = match_string("address")
      break if _tmp
      self.pos = _save
      _tmp = match_string("blockquote")
      break if _tmp
      self.pos = _save
      _tmp = match_string("center")
      break if _tmp
      self.pos = _save
      _tmp = match_string("dd")
      break if _tmp
      self.pos = _save
      _tmp = match_string("dir")
      break if _tmp
      self.pos = _save
      _tmp = match_string("div")
      break if _tmp
      self.pos = _save
      _tmp = match_string("dl")
      break if _tmp
      self.pos = _save
      _tmp = match_string("dt")
      break if _tmp
      self.pos = _save
      _tmp = match_string("fieldset")
      break if _tmp
      self.pos = _save
      _tmp = match_string("form")
      break if _tmp
      self.pos = _save
      _tmp = match_string("frameset")
      break if _tmp
      self.pos = _save
      _tmp = match_string("h1")
      break if _tmp
      self.pos = _save
      _tmp = match_string("h2")
      break if _tmp
      self.pos = _save
      _tmp = match_string("h3")
      break if _tmp
      self.pos = _save
      _tmp = match_string("h4")
      break if _tmp
      self.pos = _save
      _tmp = match_string("h5")
      break if _tmp
      self.pos = _save
      _tmp = match_string("h6")
      break if _tmp
      self.pos = _save
      _tmp = match_string("hr")
      break if _tmp
      self.pos = _save
      _tmp = match_string("isindex")
      break if _tmp
      self.pos = _save
      _tmp = match_string("li")
      break if _tmp
      self.pos = _save
      _tmp = match_string("menu")
      break if _tmp
      self.pos = _save
      _tmp = match_string("noframes")
      break if _tmp
      self.pos = _save
      _tmp = match_string("noscript")
      break if _tmp
      self.pos = _save
      _tmp = match_string("ol")
      break if _tmp
      self.pos = _save
      _tmp = match_string("p")
      break if _tmp
      self.pos = _save
      _tmp = match_string("pre")
      break if _tmp
      self.pos = _save
      _tmp = match_string("script")
      break if _tmp
      self.pos = _save
      _tmp = match_string("table")
      break if _tmp
      self.pos = _save
      _tmp = match_string("tbody")
      break if _tmp
      self.pos = _save
      _tmp = match_string("td")
      break if _tmp
      self.pos = _save
      _tmp = match_string("tfoot")
      break if _tmp
      self.pos = _save
      _tmp = match_string("th")
      break if _tmp
      self.pos = _save
      _tmp = match_string("thead")
      break if _tmp
      self.pos = _save
      _tmp = match_string("tr")
      break if _tmp
      self.pos = _save
      _tmp = match_string("ul")
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_HtmlBlockType unless _tmp
    return _tmp
  end

  # StyleOpen = "<" Spnl ("style" | "STYLE") Spnl HtmlAttribute* ">"
  def _StyleOpen

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("style")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("STYLE")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_StyleOpen unless _tmp
    return _tmp
  end

  # StyleClose = "<" Spnl "/" ("style" | "STYLE") Spnl ">"
  def _StyleClose

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("/")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = match_string("style")
        break if _tmp
        self.pos = _save1
        _tmp = match_string("STYLE")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_StyleClose unless _tmp
    return _tmp
  end

  # InStyleTags = StyleOpen (!StyleClose .)* StyleClose
  def _InStyleTags

    _save = self.pos
    while true # sequence
      _tmp = apply(:_StyleOpen)
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos
          _tmp = apply(:_StyleClose)
          _tmp = _tmp ? nil : true
          self.pos = _save3
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_StyleClose)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_InStyleTags unless _tmp
    return _tmp
  end

  # StyleBlock = < InStyleTags > @BlankLine* { if css? then                     RDoc::Markup::Raw.new text                   end }
  def _StyleBlock

    _save = self.pos
    while true # sequence
      _text_start = self.pos
      _tmp = apply(:_InStyleTags)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = _BlankLine()
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  if css? then
                    RDoc::Markup::Raw.new text
                  end ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_StyleBlock unless _tmp
    return _tmp
  end

  # Inlines = (!@Endline Inline:i { i } | @Endline:c !(&{ github? } Ticks3 /[^`\n]*$/) &Inline { c })+:chunks @Endline? { chunks }
  def _Inlines

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _ary = []

      _save2 = self.pos
      while true # choice

        _save3 = self.pos
        while true # sequence
          _save4 = self.pos
          _tmp = _Endline()
          _tmp = _tmp ? nil : true
          self.pos = _save4
          unless _tmp
            self.pos = _save3
            break
          end
          _tmp = apply(:_Inline)
          i = @result
          unless _tmp
            self.pos = _save3
            break
          end
          @result = begin;  i ; end
          _tmp = true
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save2

        _save5 = self.pos
        while true # sequence
          _tmp = _Endline()
          c = @result
          unless _tmp
            self.pos = _save5
            break
          end
          _save6 = self.pos

          _save7 = self.pos
          while true # sequence
            _save8 = self.pos
            _tmp = begin;  github? ; end
            self.pos = _save8
            unless _tmp
              self.pos = _save7
              break
            end
            _tmp = apply(:_Ticks3)
            unless _tmp
              self.pos = _save7
              break
            end
            _tmp = scan(/\G(?-mix:[^`\n]*$)/)
            unless _tmp
              self.pos = _save7
            end
            break
          end # end sequence

          _tmp = _tmp ? nil : true
          self.pos = _save6
          unless _tmp
            self.pos = _save5
            break
          end
          _save9 = self.pos
          _tmp = apply(:_Inline)
          self.pos = _save9
          unless _tmp
            self.pos = _save5
            break
          end
          @result = begin;  c ; end
          _tmp = true
          unless _tmp
            self.pos = _save5
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save2
        break
      end # end choice

      if _tmp
        _ary << @result
        while true

          _save10 = self.pos
          while true # choice

            _save11 = self.pos
            while true # sequence
              _save12 = self.pos
              _tmp = _Endline()
              _tmp = _tmp ? nil : true
              self.pos = _save12
              unless _tmp
                self.pos = _save11
                break
              end
              _tmp = apply(:_Inline)
              i = @result
              unless _tmp
                self.pos = _save11
                break
              end
              @result = begin;  i ; end
              _tmp = true
              unless _tmp
                self.pos = _save11
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save10

            _save13 = self.pos
            while true # sequence
              _tmp = _Endline()
              c = @result
              unless _tmp
                self.pos = _save13
                break
              end
              _save14 = self.pos

              _save15 = self.pos
              while true # sequence
                _save16 = self.pos
                _tmp = begin;  github? ; end
                self.pos = _save16
                unless _tmp
                  self.pos = _save15
                  break
                end
                _tmp = apply(:_Ticks3)
                unless _tmp
                  self.pos = _save15
                  break
                end
                _tmp = scan(/\G(?-mix:[^`\n]*$)/)
                unless _tmp
                  self.pos = _save15
                end
                break
              end # end sequence

              _tmp = _tmp ? nil : true
              self.pos = _save14
              unless _tmp
                self.pos = _save13
                break
              end
              _save17 = self.pos
              _tmp = apply(:_Inline)
              self.pos = _save17
              unless _tmp
                self.pos = _save13
                break
              end
              @result = begin;  c ; end
              _tmp = true
              unless _tmp
                self.pos = _save13
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save10
            break
          end # end choice

          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save1
      end
      chunks = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save18 = self.pos
      _tmp = _Endline()
      unless _tmp
        _tmp = true
        self.pos = _save18
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  chunks ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Inlines unless _tmp
    return _tmp
  end

  # Inline = (Str | @Endline | UlOrStarLine | @Space | Strong | Emph | Strike | Image | Link | NoteReference | InlineNote | Code | RawHtml | Entity | EscapedChar | Symbol)
  def _Inline

    _save = self.pos
    while true # choice
      _tmp = apply(:_Str)
      break if _tmp
      self.pos = _save
      _tmp = _Endline()
      break if _tmp
      self.pos = _save
      _tmp = apply(:_UlOrStarLine)
      break if _tmp
      self.pos = _save
      _tmp = _Space()
      break if _tmp
      self.pos = _save
      _tmp = apply(:_Strong)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_Emph)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_Strike)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_Image)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_Link)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_NoteReference)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_InlineNote)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_Code)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_RawHtml)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_Entity)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_EscapedChar)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_Symbol)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_Inline unless _tmp
    return _tmp
  end

  # Space = @Spacechar+ { " " }
  def _Space

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = _Spacechar()
      if _tmp
        while true
          _tmp = _Spacechar()
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  " " ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Space unless _tmp
    return _tmp
  end

  # Str = @StartList:a < @NormalChar+ > { a = text } (StrChunk:c { a << c })* { a }
  def _Str

    _save = self.pos
    while true # sequence
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _save1 = self.pos
      _tmp = _NormalChar()
      if _tmp
        while true
          _tmp = _NormalChar()
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a = text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save3 = self.pos
        while true # sequence
          _tmp = apply(:_StrChunk)
          c = @result
          unless _tmp
            self.pos = _save3
            break
          end
          @result = begin;  a << c ; end
          _tmp = true
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Str unless _tmp
    return _tmp
  end

  # StrChunk = < (@NormalChar | /_+/ &Alphanumeric)+ > { text }
  def _StrChunk

    _save = self.pos
    while true # sequence
      _text_start = self.pos
      _save1 = self.pos

      _save2 = self.pos
      while true # choice
        _tmp = _NormalChar()
        break if _tmp
        self.pos = _save2

        _save3 = self.pos
        while true # sequence
          _tmp = scan(/\G(?-mix:_+)/)
          unless _tmp
            self.pos = _save3
            break
          end
          _save4 = self.pos
          _tmp = apply(:_Alphanumeric)
          self.pos = _save4
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save2
        break
      end # end choice

      if _tmp
        while true

          _save5 = self.pos
          while true # choice
            _tmp = _NormalChar()
            break if _tmp
            self.pos = _save5

            _save6 = self.pos
            while true # sequence
              _tmp = scan(/\G(?-mix:_+)/)
              unless _tmp
                self.pos = _save6
                break
              end
              _save7 = self.pos
              _tmp = apply(:_Alphanumeric)
              self.pos = _save7
              unless _tmp
                self.pos = _save6
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save5
            break
          end # end choice

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_StrChunk unless _tmp
    return _tmp
  end

  # EscapedChar = "\\" !@Newline < /[:\\`|*_{}\[\]()#+.!><-]/ > { text }
  def _EscapedChar

    _save = self.pos
    while true # sequence
      _tmp = match_string("\\")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = _Newline()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _tmp = scan(/\G(?-mix:[:\\`|*_{}\[\]()#+.!><-])/)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_EscapedChar unless _tmp
    return _tmp
  end

  # Entity = (HexEntity | DecEntity | CharEntity):a { a }
  def _Entity

    _save = self.pos
    while true # sequence

      _save1 = self.pos
      while true # choice
        _tmp = apply(:_HexEntity)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_DecEntity)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_CharEntity)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Entity unless _tmp
    return _tmp
  end

  # Endline = (@LineBreak | @TerminalEndline | @NormalEndline)
  def _Endline

    _save = self.pos
    while true # choice
      _tmp = _LineBreak()
      break if _tmp
      self.pos = _save
      _tmp = _TerminalEndline()
      break if _tmp
      self.pos = _save
      _tmp = _NormalEndline()
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_Endline unless _tmp
    return _tmp
  end

  # NormalEndline = @Sp @Newline !@BlankLine !">" !AtxStart !(Line /={1,}|-{1,}/ @Newline) { "\n" }
  def _NormalEndline

    _save = self.pos
    while true # sequence
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = _BlankLine()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _tmp = match_string(">")
      _tmp = _tmp ? nil : true
      self.pos = _save2
      unless _tmp
        self.pos = _save
        break
      end
      _save3 = self.pos
      _tmp = apply(:_AtxStart)
      _tmp = _tmp ? nil : true
      self.pos = _save3
      unless _tmp
        self.pos = _save
        break
      end
      _save4 = self.pos

      _save5 = self.pos
      while true # sequence
        _tmp = apply(:_Line)
        unless _tmp
          self.pos = _save5
          break
        end
        _tmp = scan(/\G(?-mix:={1,}|-{1,})/)
        unless _tmp
          self.pos = _save5
          break
        end
        _tmp = _Newline()
        unless _tmp
          self.pos = _save5
        end
        break
      end # end sequence

      _tmp = _tmp ? nil : true
      self.pos = _save4
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  "\n" ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_NormalEndline unless _tmp
    return _tmp
  end

  # TerminalEndline = @Sp @Newline @Eof
  def _TerminalEndline

    _save = self.pos
    while true # sequence
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Eof()
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_TerminalEndline unless _tmp
    return _tmp
  end

  # LineBreak = "  " @NormalEndline { RDoc::Markup::HardBreak.new }
  def _LineBreak

    _save = self.pos
    while true # sequence
      _tmp = match_string("  ")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _NormalEndline()
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::HardBreak.new ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_LineBreak unless _tmp
    return _tmp
  end

  # Symbol = < @SpecialChar > { text }
  def _Symbol

    _save = self.pos
    while true # sequence
      _text_start = self.pos
      _tmp = _SpecialChar()
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Symbol unless _tmp
    return _tmp
  end

  # UlOrStarLine = (UlLine | StarLine):a { a }
  def _UlOrStarLine

    _save = self.pos
    while true # sequence

      _save1 = self.pos
      while true # choice
        _tmp = apply(:_UlLine)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_StarLine)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_UlOrStarLine unless _tmp
    return _tmp
  end

  # StarLine = (< /\*{4,}/ > { text } | < @Spacechar /\*+/ &@Spacechar > { text })
  def _StarLine

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _text_start = self.pos
        _tmp = scan(/\G(?-mix:\*{4,})/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  text ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _text_start = self.pos

        _save3 = self.pos
        while true # sequence
          _tmp = _Spacechar()
          unless _tmp
            self.pos = _save3
            break
          end
          _tmp = scan(/\G(?-mix:\*+)/)
          unless _tmp
            self.pos = _save3
            break
          end
          _save4 = self.pos
          _tmp = _Spacechar()
          self.pos = _save4
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  text ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_StarLine unless _tmp
    return _tmp
  end

  # UlLine = (< /_{4,}/ > { text } | < @Spacechar /_+/ &@Spacechar > { text })
  def _UlLine

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _text_start = self.pos
        _tmp = scan(/\G(?-mix:_{4,})/)
        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save1
          break
        end
        @result = begin;  text ; end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save2 = self.pos
      while true # sequence
        _text_start = self.pos

        _save3 = self.pos
        while true # sequence
          _tmp = _Spacechar()
          unless _tmp
            self.pos = _save3
            break
          end
          _tmp = scan(/\G(?-mix:_+)/)
          unless _tmp
            self.pos = _save3
            break
          end
          _save4 = self.pos
          _tmp = _Spacechar()
          self.pos = _save4
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        if _tmp
          text = get_text(_text_start)
        end
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  text ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_UlLine unless _tmp
    return _tmp
  end

  # Emph = (EmphStar | EmphUl)
  def _Emph

    _save = self.pos
    while true # choice
      _tmp = apply(:_EmphStar)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_EmphUl)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_Emph unless _tmp
    return _tmp
  end

  # Whitespace = (@Spacechar | @Newline)
  def _Whitespace

    _save = self.pos
    while true # choice
      _tmp = _Spacechar()
      break if _tmp
      self.pos = _save
      _tmp = _Newline()
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_Whitespace unless _tmp
    return _tmp
  end

  # EmphStar = "*" !@Whitespace @StartList:a (!"*" Inline:b { a << b } | StrongStar:b { a << b })+ "*" { emphasis a.join }
  def _EmphStar

    _save = self.pos
    while true # sequence
      _tmp = match_string("*")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = _Whitespace()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos

      _save3 = self.pos
      while true # choice

        _save4 = self.pos
        while true # sequence
          _save5 = self.pos
          _tmp = match_string("*")
          _tmp = _tmp ? nil : true
          self.pos = _save5
          unless _tmp
            self.pos = _save4
            break
          end
          _tmp = apply(:_Inline)
          b = @result
          unless _tmp
            self.pos = _save4
            break
          end
          @result = begin;  a << b ; end
          _tmp = true
          unless _tmp
            self.pos = _save4
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save3

        _save6 = self.pos
        while true # sequence
          _tmp = apply(:_StrongStar)
          b = @result
          unless _tmp
            self.pos = _save6
            break
          end
          @result = begin;  a << b ; end
          _tmp = true
          unless _tmp
            self.pos = _save6
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save3
        break
      end # end choice

      if _tmp
        while true

          _save7 = self.pos
          while true # choice

            _save8 = self.pos
            while true # sequence
              _save9 = self.pos
              _tmp = match_string("*")
              _tmp = _tmp ? nil : true
              self.pos = _save9
              unless _tmp
                self.pos = _save8
                break
              end
              _tmp = apply(:_Inline)
              b = @result
              unless _tmp
                self.pos = _save8
                break
              end
              @result = begin;  a << b ; end
              _tmp = true
              unless _tmp
                self.pos = _save8
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save7

            _save10 = self.pos
            while true # sequence
              _tmp = apply(:_StrongStar)
              b = @result
              unless _tmp
                self.pos = _save10
                break
              end
              @result = begin;  a << b ; end
              _tmp = true
              unless _tmp
                self.pos = _save10
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save7
            break
          end # end choice

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("*")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  emphasis a.join ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_EmphStar unless _tmp
    return _tmp
  end

  # EmphUl = "_" !@Whitespace @StartList:a (!"_" Inline:b { a << b } | StrongUl:b { a << b })+ "_" { emphasis a.join }
  def _EmphUl

    _save = self.pos
    while true # sequence
      _tmp = match_string("_")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = _Whitespace()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos

      _save3 = self.pos
      while true # choice

        _save4 = self.pos
        while true # sequence
          _save5 = self.pos
          _tmp = match_string("_")
          _tmp = _tmp ? nil : true
          self.pos = _save5
          unless _tmp
            self.pos = _save4
            break
          end
          _tmp = apply(:_Inline)
          b = @result
          unless _tmp
            self.pos = _save4
            break
          end
          @result = begin;  a << b ; end
          _tmp = true
          unless _tmp
            self.pos = _save4
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save3

        _save6 = self.pos
        while true # sequence
          _tmp = apply(:_StrongUl)
          b = @result
          unless _tmp
            self.pos = _save6
            break
          end
          @result = begin;  a << b ; end
          _tmp = true
          unless _tmp
            self.pos = _save6
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save3
        break
      end # end choice

      if _tmp
        while true

          _save7 = self.pos
          while true # choice

            _save8 = self.pos
            while true # sequence
              _save9 = self.pos
              _tmp = match_string("_")
              _tmp = _tmp ? nil : true
              self.pos = _save9
              unless _tmp
                self.pos = _save8
                break
              end
              _tmp = apply(:_Inline)
              b = @result
              unless _tmp
                self.pos = _save8
                break
              end
              @result = begin;  a << b ; end
              _tmp = true
              unless _tmp
                self.pos = _save8
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save7

            _save10 = self.pos
            while true # sequence
              _tmp = apply(:_StrongUl)
              b = @result
              unless _tmp
                self.pos = _save10
                break
              end
              @result = begin;  a << b ; end
              _tmp = true
              unless _tmp
                self.pos = _save10
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save7
            break
          end # end choice

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("_")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  emphasis a.join ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_EmphUl unless _tmp
    return _tmp
  end

  # Strong = (StrongStar | StrongUl)
  def _Strong

    _save = self.pos
    while true # choice
      _tmp = apply(:_StrongStar)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_StrongUl)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_Strong unless _tmp
    return _tmp
  end

  # StrongStar = "**" !@Whitespace @StartList:a (!"**" Inline:b { a << b })+ "**" { strong a.join }
  def _StrongStar

    _save = self.pos
    while true # sequence
      _tmp = match_string("**")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = _Whitespace()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos

      _save3 = self.pos
      while true # sequence
        _save4 = self.pos
        _tmp = match_string("**")
        _tmp = _tmp ? nil : true
        self.pos = _save4
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = apply(:_Inline)
        b = @result
        unless _tmp
          self.pos = _save3
          break
        end
        @result = begin;  a << b ; end
        _tmp = true
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      if _tmp
        while true

          _save5 = self.pos
          while true # sequence
            _save6 = self.pos
            _tmp = match_string("**")
            _tmp = _tmp ? nil : true
            self.pos = _save6
            unless _tmp
              self.pos = _save5
              break
            end
            _tmp = apply(:_Inline)
            b = @result
            unless _tmp
              self.pos = _save5
              break
            end
            @result = begin;  a << b ; end
            _tmp = true
            unless _tmp
              self.pos = _save5
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("**")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  strong a.join ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_StrongStar unless _tmp
    return _tmp
  end

  # StrongUl = "__" !@Whitespace @StartList:a (!"__" Inline:b { a << b })+ "__" { strong a.join }
  def _StrongUl

    _save = self.pos
    while true # sequence
      _tmp = match_string("__")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = _Whitespace()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos

      _save3 = self.pos
      while true # sequence
        _save4 = self.pos
        _tmp = match_string("__")
        _tmp = _tmp ? nil : true
        self.pos = _save4
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = apply(:_Inline)
        b = @result
        unless _tmp
          self.pos = _save3
          break
        end
        @result = begin;  a << b ; end
        _tmp = true
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      if _tmp
        while true

          _save5 = self.pos
          while true # sequence
            _save6 = self.pos
            _tmp = match_string("__")
            _tmp = _tmp ? nil : true
            self.pos = _save6
            unless _tmp
              self.pos = _save5
              break
            end
            _tmp = apply(:_Inline)
            b = @result
            unless _tmp
              self.pos = _save5
              break
            end
            @result = begin;  a << b ; end
            _tmp = true
            unless _tmp
              self.pos = _save5
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("__")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  strong a.join ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_StrongUl unless _tmp
    return _tmp
  end

  # Strike = &{ strike? } "~~" !@Whitespace @StartList:a (!"~~" Inline:b { a << b })+ "~~" { strike a.join }
  def _Strike

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = begin;  strike? ; end
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("~~")
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _tmp = _Whitespace()
      _tmp = _tmp ? nil : true
      self.pos = _save2
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save3 = self.pos

      _save4 = self.pos
      while true # sequence
        _save5 = self.pos
        _tmp = match_string("~~")
        _tmp = _tmp ? nil : true
        self.pos = _save5
        unless _tmp
          self.pos = _save4
          break
        end
        _tmp = apply(:_Inline)
        b = @result
        unless _tmp
          self.pos = _save4
          break
        end
        @result = begin;  a << b ; end
        _tmp = true
        unless _tmp
          self.pos = _save4
        end
        break
      end # end sequence

      if _tmp
        while true

          _save6 = self.pos
          while true # sequence
            _save7 = self.pos
            _tmp = match_string("~~")
            _tmp = _tmp ? nil : true
            self.pos = _save7
            unless _tmp
              self.pos = _save6
              break
            end
            _tmp = apply(:_Inline)
            b = @result
            unless _tmp
              self.pos = _save6
              break
            end
            @result = begin;  a << b ; end
            _tmp = true
            unless _tmp
              self.pos = _save6
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save3
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("~~")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  strike a.join ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Strike unless _tmp
    return _tmp
  end

  # Image = "!" (ExplicitLink | ReferenceLink):a { "rdoc-image:#{a[/\[(.*)\]/, 1]}" }
  def _Image

    _save = self.pos
    while true # sequence
      _tmp = match_string("!")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice
        _tmp = apply(:_ExplicitLink)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_ReferenceLink)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  "rdoc-image:#{a[/\[(.*)\]/, 1]}" ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Image unless _tmp
    return _tmp
  end

  # Link = (ExplicitLink | ReferenceLink | AutoLink)
  def _Link

    _save = self.pos
    while true # choice
      _tmp = apply(:_ExplicitLink)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_ReferenceLink)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_AutoLink)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_Link unless _tmp
    return _tmp
  end

  # ReferenceLink = (ReferenceLinkDouble | ReferenceLinkSingle)
  def _ReferenceLink

    _save = self.pos
    while true # choice
      _tmp = apply(:_ReferenceLinkDouble)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_ReferenceLinkSingle)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_ReferenceLink unless _tmp
    return _tmp
  end

  # ReferenceLinkDouble = Label:content < Spnl > !"[]" Label:label { link_to content, label, text }
  def _ReferenceLinkDouble

    _save = self.pos
    while true # sequence
      _tmp = apply(:_Label)
      content = @result
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _tmp = apply(:_Spnl)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = match_string("[]")
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Label)
      label = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  link_to content, label, text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ReferenceLinkDouble unless _tmp
    return _tmp
  end

  # ReferenceLinkSingle = Label:content < (Spnl "[]")? > { link_to content, content, text }
  def _ReferenceLinkSingle

    _save = self.pos
    while true # sequence
      _tmp = apply(:_Label)
      content = @result
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _save1 = self.pos

      _save2 = self.pos
      while true # sequence
        _tmp = apply(:_Spnl)
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = match_string("[]")
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      unless _tmp
        _tmp = true
        self.pos = _save1
      end
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  link_to content, content, text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ReferenceLinkSingle unless _tmp
    return _tmp
  end

  # ExplicitLink = Label:l "(" @Sp Source:s Spnl Title @Sp ")" { "{#{l}}[#{s}]" }
  def _ExplicitLink

    _save = self.pos
    while true # sequence
      _tmp = apply(:_Label)
      l = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("(")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Source)
      s = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Title)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(")")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  "{#{l}}[#{s}]" ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ExplicitLink unless _tmp
    return _tmp
  end

  # Source = ("<" < SourceContents > ">" | < SourceContents >) { text }
  def _Source

    _save = self.pos
    while true # sequence

      _save1 = self.pos
      while true # choice

        _save2 = self.pos
        while true # sequence
          _tmp = match_string("<")
          unless _tmp
            self.pos = _save2
            break
          end
          _text_start = self.pos
          _tmp = apply(:_SourceContents)
          if _tmp
            text = get_text(_text_start)
          end
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = match_string(">")
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1
        _text_start = self.pos
        _tmp = apply(:_SourceContents)
        if _tmp
          text = get_text(_text_start)
        end
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Source unless _tmp
    return _tmp
  end

  # SourceContents = ((!"(" !")" !">" Nonspacechar)+ | "(" SourceContents ")")*
  def _SourceContents
    while true

      _save1 = self.pos
      while true # choice
        _save2 = self.pos

        _save3 = self.pos
        while true # sequence
          _save4 = self.pos
          _tmp = match_string("(")
          _tmp = _tmp ? nil : true
          self.pos = _save4
          unless _tmp
            self.pos = _save3
            break
          end
          _save5 = self.pos
          _tmp = match_string(")")
          _tmp = _tmp ? nil : true
          self.pos = _save5
          unless _tmp
            self.pos = _save3
            break
          end
          _save6 = self.pos
          _tmp = match_string(">")
          _tmp = _tmp ? nil : true
          self.pos = _save6
          unless _tmp
            self.pos = _save3
            break
          end
          _tmp = apply(:_Nonspacechar)
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        if _tmp
          while true

            _save7 = self.pos
            while true # sequence
              _save8 = self.pos
              _tmp = match_string("(")
              _tmp = _tmp ? nil : true
              self.pos = _save8
              unless _tmp
                self.pos = _save7
                break
              end
              _save9 = self.pos
              _tmp = match_string(")")
              _tmp = _tmp ? nil : true
              self.pos = _save9
              unless _tmp
                self.pos = _save7
                break
              end
              _save10 = self.pos
              _tmp = match_string(">")
              _tmp = _tmp ? nil : true
              self.pos = _save10
              unless _tmp
                self.pos = _save7
                break
              end
              _tmp = apply(:_Nonspacechar)
              unless _tmp
                self.pos = _save7
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
        else
          self.pos = _save2
        end
        break if _tmp
        self.pos = _save1

        _save11 = self.pos
        while true # sequence
          _tmp = match_string("(")
          unless _tmp
            self.pos = _save11
            break
          end
          _tmp = apply(:_SourceContents)
          unless _tmp
            self.pos = _save11
            break
          end
          _tmp = match_string(")")
          unless _tmp
            self.pos = _save11
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1
        break
      end # end choice

      break unless _tmp
    end
    _tmp = true
    set_failed_rule :_SourceContents unless _tmp
    return _tmp
  end

  # Title = (TitleSingle | TitleDouble | ""):a { a }
  def _Title

    _save = self.pos
    while true # sequence

      _save1 = self.pos
      while true # choice
        _tmp = apply(:_TitleSingle)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_TitleDouble)
        break if _tmp
        self.pos = _save1
        _tmp = match_string("")
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Title unless _tmp
    return _tmp
  end

  # TitleSingle = "'" (!("'" @Sp (")" | @Newline)) .)* "'"
  def _TitleSingle

    _save = self.pos
    while true # sequence
      _tmp = match_string("'")
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos

          _save4 = self.pos
          while true # sequence
            _tmp = match_string("'")
            unless _tmp
              self.pos = _save4
              break
            end
            _tmp = _Sp()
            unless _tmp
              self.pos = _save4
              break
            end

            _save5 = self.pos
            while true # choice
              _tmp = match_string(")")
              break if _tmp
              self.pos = _save5
              _tmp = _Newline()
              break if _tmp
              self.pos = _save5
              break
            end # end choice

            unless _tmp
              self.pos = _save4
            end
            break
          end # end sequence

          _tmp = _tmp ? nil : true
          self.pos = _save3
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("'")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_TitleSingle unless _tmp
    return _tmp
  end

  # TitleDouble = "\"" (!("\"" @Sp (")" | @Newline)) .)* "\""
  def _TitleDouble

    _save = self.pos
    while true # sequence
      _tmp = match_string("\"")
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos

          _save4 = self.pos
          while true # sequence
            _tmp = match_string("\"")
            unless _tmp
              self.pos = _save4
              break
            end
            _tmp = _Sp()
            unless _tmp
              self.pos = _save4
              break
            end

            _save5 = self.pos
            while true # choice
              _tmp = match_string(")")
              break if _tmp
              self.pos = _save5
              _tmp = _Newline()
              break if _tmp
              self.pos = _save5
              break
            end # end choice

            unless _tmp
              self.pos = _save4
            end
            break
          end # end sequence

          _tmp = _tmp ? nil : true
          self.pos = _save3
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("\"")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_TitleDouble unless _tmp
    return _tmp
  end

  # AutoLink = (AutoLinkUrl | AutoLinkEmail)
  def _AutoLink

    _save = self.pos
    while true # choice
      _tmp = apply(:_AutoLinkUrl)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_AutoLinkEmail)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_AutoLink unless _tmp
    return _tmp
  end

  # AutoLinkUrl = "<" < /[A-Za-z]+/ "://" (!@Newline !">" .)+ > ">" { text }
  def _AutoLinkUrl

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos

      _save1 = self.pos
      while true # sequence
        _tmp = scan(/\G(?-mix:[A-Za-z]+)/)
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = match_string("://")
        unless _tmp
          self.pos = _save1
          break
        end
        _save2 = self.pos

        _save3 = self.pos
        while true # sequence
          _save4 = self.pos
          _tmp = _Newline()
          _tmp = _tmp ? nil : true
          self.pos = _save4
          unless _tmp
            self.pos = _save3
            break
          end
          _save5 = self.pos
          _tmp = match_string(">")
          _tmp = _tmp ? nil : true
          self.pos = _save5
          unless _tmp
            self.pos = _save3
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        if _tmp
          while true

            _save6 = self.pos
            while true # sequence
              _save7 = self.pos
              _tmp = _Newline()
              _tmp = _tmp ? nil : true
              self.pos = _save7
              unless _tmp
                self.pos = _save6
                break
              end
              _save8 = self.pos
              _tmp = match_string(">")
              _tmp = _tmp ? nil : true
              self.pos = _save8
              unless _tmp
                self.pos = _save6
                break
              end
              _tmp = get_byte
              unless _tmp
                self.pos = _save6
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
        else
          self.pos = _save2
        end
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_AutoLinkUrl unless _tmp
    return _tmp
  end

  # AutoLinkEmail = "<" "mailto:"? < /[\w+.\/!%~$-]+/i "@" (!@Newline !">" .)+ > ">" { "mailto:#{text}" }
  def _AutoLinkEmail

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = match_string("mailto:")
      unless _tmp
        _tmp = true
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos

      _save2 = self.pos
      while true # sequence
        _tmp = scan(/\G(?i-mx:[\w+.\/!%~$-]+)/)
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = match_string("@")
        unless _tmp
          self.pos = _save2
          break
        end
        _save3 = self.pos

        _save4 = self.pos
        while true # sequence
          _save5 = self.pos
          _tmp = _Newline()
          _tmp = _tmp ? nil : true
          self.pos = _save5
          unless _tmp
            self.pos = _save4
            break
          end
          _save6 = self.pos
          _tmp = match_string(">")
          _tmp = _tmp ? nil : true
          self.pos = _save6
          unless _tmp
            self.pos = _save4
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save4
          end
          break
        end # end sequence

        if _tmp
          while true

            _save7 = self.pos
            while true # sequence
              _save8 = self.pos
              _tmp = _Newline()
              _tmp = _tmp ? nil : true
              self.pos = _save8
              unless _tmp
                self.pos = _save7
                break
              end
              _save9 = self.pos
              _tmp = match_string(">")
              _tmp = _tmp ? nil : true
              self.pos = _save9
              unless _tmp
                self.pos = _save7
                break
              end
              _tmp = get_byte
              unless _tmp
                self.pos = _save7
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
        else
          self.pos = _save3
        end
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  "mailto:#{text}" ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_AutoLinkEmail unless _tmp
    return _tmp
  end

  # Reference = @NonindentSpace !"[]" Label:label ":" Spnl RefSrc:link RefTitle @BlankLine+ { # TODO use title               reference label, link               nil             }
  def _Reference

    _save = self.pos
    while true # sequence
      _tmp = _NonindentSpace()
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = match_string("[]")
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Label)
      label = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(":")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_RefSrc)
      link = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_RefTitle)
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _tmp = _BlankLine()
      if _tmp
        while true
          _tmp = _BlankLine()
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  # TODO use title
              reference label, link
              nil
            ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Reference unless _tmp
    return _tmp
  end

  # Label = "[" (!"^" &{ notes? } | &. &{ !notes? }) @StartList:a (!"]" Inline:l { a << l })* "]" { a.join.gsub(/\s+/, ' ') }
  def _Label

    _save = self.pos
    while true # sequence
      _tmp = match_string("[")
      unless _tmp
        self.pos = _save
        break
      end

      _save1 = self.pos
      while true # choice

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos
          _tmp = match_string("^")
          _tmp = _tmp ? nil : true
          self.pos = _save3
          unless _tmp
            self.pos = _save2
            break
          end
          _save4 = self.pos
          _tmp = begin;  notes? ; end
          self.pos = _save4
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1

        _save5 = self.pos
        while true # sequence
          _save6 = self.pos
          _tmp = get_byte
          self.pos = _save6
          unless _tmp
            self.pos = _save5
            break
          end
          _save7 = self.pos
          _tmp = begin;  !notes? ; end
          self.pos = _save7
          unless _tmp
            self.pos = _save5
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save9 = self.pos
        while true # sequence
          _save10 = self.pos
          _tmp = match_string("]")
          _tmp = _tmp ? nil : true
          self.pos = _save10
          unless _tmp
            self.pos = _save9
            break
          end
          _tmp = apply(:_Inline)
          l = @result
          unless _tmp
            self.pos = _save9
            break
          end
          @result = begin;  a << l ; end
          _tmp = true
          unless _tmp
            self.pos = _save9
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("]")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a.join.gsub(/\s+/, ' ') ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Label unless _tmp
    return _tmp
  end

  # RefSrc = < Nonspacechar+ > { text }
  def _RefSrc

    _save = self.pos
    while true # sequence
      _text_start = self.pos
      _save1 = self.pos
      _tmp = apply(:_Nonspacechar)
      if _tmp
        while true
          _tmp = apply(:_Nonspacechar)
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_RefSrc unless _tmp
    return _tmp
  end

  # RefTitle = (RefTitleSingle | RefTitleDouble | RefTitleParens | EmptyTitle)
  def _RefTitle

    _save = self.pos
    while true # choice
      _tmp = apply(:_RefTitleSingle)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_RefTitleDouble)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_RefTitleParens)
      break if _tmp
      self.pos = _save
      _tmp = apply(:_EmptyTitle)
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_RefTitle unless _tmp
    return _tmp
  end

  # EmptyTitle = ""
  def _EmptyTitle
    _tmp = match_string("")
    set_failed_rule :_EmptyTitle unless _tmp
    return _tmp
  end

  # RefTitleSingle = Spnl "'" < (!("'" @Sp @Newline | @Newline) .)* > "'" { text }
  def _RefTitleSingle

    _save = self.pos
    while true # sequence
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("'")
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      while true

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos

          _save4 = self.pos
          while true # choice

            _save5 = self.pos
            while true # sequence
              _tmp = match_string("'")
              unless _tmp
                self.pos = _save5
                break
              end
              _tmp = _Sp()
              unless _tmp
                self.pos = _save5
                break
              end
              _tmp = _Newline()
              unless _tmp
                self.pos = _save5
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save4
            _tmp = _Newline()
            break if _tmp
            self.pos = _save4
            break
          end # end choice

          _tmp = _tmp ? nil : true
          self.pos = _save3
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("'")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_RefTitleSingle unless _tmp
    return _tmp
  end

  # RefTitleDouble = Spnl "\"" < (!("\"" @Sp @Newline | @Newline) .)* > "\"" { text }
  def _RefTitleDouble

    _save = self.pos
    while true # sequence
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("\"")
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      while true

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos

          _save4 = self.pos
          while true # choice

            _save5 = self.pos
            while true # sequence
              _tmp = match_string("\"")
              unless _tmp
                self.pos = _save5
                break
              end
              _tmp = _Sp()
              unless _tmp
                self.pos = _save5
                break
              end
              _tmp = _Newline()
              unless _tmp
                self.pos = _save5
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save4
            _tmp = _Newline()
            break if _tmp
            self.pos = _save4
            break
          end # end choice

          _tmp = _tmp ? nil : true
          self.pos = _save3
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("\"")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_RefTitleDouble unless _tmp
    return _tmp
  end

  # RefTitleParens = Spnl "(" < (!(")" @Sp @Newline | @Newline) .)* > ")" { text }
  def _RefTitleParens

    _save = self.pos
    while true # sequence
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("(")
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      while true

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos

          _save4 = self.pos
          while true # choice

            _save5 = self.pos
            while true # sequence
              _tmp = match_string(")")
              unless _tmp
                self.pos = _save5
                break
              end
              _tmp = _Sp()
              unless _tmp
                self.pos = _save5
                break
              end
              _tmp = _Newline()
              unless _tmp
                self.pos = _save5
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save4
            _tmp = _Newline()
            break if _tmp
            self.pos = _save4
            break
          end # end choice

          _tmp = _tmp ? nil : true
          self.pos = _save3
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(")")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_RefTitleParens unless _tmp
    return _tmp
  end

  # References = (Reference | SkipBlock)*
  def _References
    while true

      _save1 = self.pos
      while true # choice
        _tmp = apply(:_Reference)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_SkipBlock)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      break unless _tmp
    end
    _tmp = true
    set_failed_rule :_References unless _tmp
    return _tmp
  end

  # Ticks1 = "`" !"`"
  def _Ticks1

    _save = self.pos
    while true # sequence
      _tmp = match_string("`")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = match_string("`")
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Ticks1 unless _tmp
    return _tmp
  end

  # Ticks2 = "``" !"`"
  def _Ticks2

    _save = self.pos
    while true # sequence
      _tmp = match_string("``")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = match_string("`")
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Ticks2 unless _tmp
    return _tmp
  end

  # Ticks3 = "```" !"`"
  def _Ticks3

    _save = self.pos
    while true # sequence
      _tmp = match_string("```")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = match_string("`")
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Ticks3 unless _tmp
    return _tmp
  end

  # Ticks4 = "````" !"`"
  def _Ticks4

    _save = self.pos
    while true # sequence
      _tmp = match_string("````")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = match_string("`")
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Ticks4 unless _tmp
    return _tmp
  end

  # Ticks5 = "`````" !"`"
  def _Ticks5

    _save = self.pos
    while true # sequence
      _tmp = match_string("`````")
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = match_string("`")
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Ticks5 unless _tmp
    return _tmp
  end

  # Code = (Ticks1 @Sp < ((!"`" Nonspacechar)+ | !Ticks1 /`+/ | !(@Sp Ticks1) (@Spacechar | @Newline !@BlankLine))+ > @Sp Ticks1 | Ticks2 @Sp < ((!"`" Nonspacechar)+ | !Ticks2 /`+/ | !(@Sp Ticks2) (@Spacechar | @Newline !@BlankLine))+ > @Sp Ticks2 | Ticks3 @Sp < ((!"`" Nonspacechar)+ | !Ticks3 /`+/ | !(@Sp Ticks3) (@Spacechar | @Newline !@BlankLine))+ > @Sp Ticks3 | Ticks4 @Sp < ((!"`" Nonspacechar)+ | !Ticks4 /`+/ | !(@Sp Ticks4) (@Spacechar | @Newline !@BlankLine))+ > @Sp Ticks4 | Ticks5 @Sp < ((!"`" Nonspacechar)+ | !Ticks5 /`+/ | !(@Sp Ticks5) (@Spacechar | @Newline !@BlankLine))+ > @Sp Ticks5) { "<code>#{text}</code>" }
  def _Code

    _save = self.pos
    while true # sequence

      _save1 = self.pos
      while true # choice

        _save2 = self.pos
        while true # sequence
          _tmp = apply(:_Ticks1)
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save2
            break
          end
          _text_start = self.pos
          _save3 = self.pos

          _save4 = self.pos
          while true # choice
            _save5 = self.pos

            _save6 = self.pos
            while true # sequence
              _save7 = self.pos
              _tmp = match_string("`")
              _tmp = _tmp ? nil : true
              self.pos = _save7
              unless _tmp
                self.pos = _save6
                break
              end
              _tmp = apply(:_Nonspacechar)
              unless _tmp
                self.pos = _save6
              end
              break
            end # end sequence

            if _tmp
              while true

                _save8 = self.pos
                while true # sequence
                  _save9 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save9
                  unless _tmp
                    self.pos = _save8
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save8
                  end
                  break
                end # end sequence

                break unless _tmp
              end
              _tmp = true
            else
              self.pos = _save5
            end
            break if _tmp
            self.pos = _save4

            _save10 = self.pos
            while true # sequence
              _save11 = self.pos
              _tmp = apply(:_Ticks1)
              _tmp = _tmp ? nil : true
              self.pos = _save11
              unless _tmp
                self.pos = _save10
                break
              end
              _tmp = scan(/\G(?-mix:`+)/)
              unless _tmp
                self.pos = _save10
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save4

            _save12 = self.pos
            while true # sequence
              _save13 = self.pos

              _save14 = self.pos
              while true # sequence
                _tmp = _Sp()
                unless _tmp
                  self.pos = _save14
                  break
                end
                _tmp = apply(:_Ticks1)
                unless _tmp
                  self.pos = _save14
                end
                break
              end # end sequence

              _tmp = _tmp ? nil : true
              self.pos = _save13
              unless _tmp
                self.pos = _save12
                break
              end

              _save15 = self.pos
              while true # choice
                _tmp = _Spacechar()
                break if _tmp
                self.pos = _save15

                _save16 = self.pos
                while true # sequence
                  _tmp = _Newline()
                  unless _tmp
                    self.pos = _save16
                    break
                  end
                  _save17 = self.pos
                  _tmp = _BlankLine()
                  _tmp = _tmp ? nil : true
                  self.pos = _save17
                  unless _tmp
                    self.pos = _save16
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save15
                break
              end # end choice

              unless _tmp
                self.pos = _save12
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save4
            break
          end # end choice

          if _tmp
            while true

              _save18 = self.pos
              while true # choice
                _save19 = self.pos

                _save20 = self.pos
                while true # sequence
                  _save21 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save21
                  unless _tmp
                    self.pos = _save20
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save20
                  end
                  break
                end # end sequence

                if _tmp
                  while true

                    _save22 = self.pos
                    while true # sequence
                      _save23 = self.pos
                      _tmp = match_string("`")
                      _tmp = _tmp ? nil : true
                      self.pos = _save23
                      unless _tmp
                        self.pos = _save22
                        break
                      end
                      _tmp = apply(:_Nonspacechar)
                      unless _tmp
                        self.pos = _save22
                      end
                      break
                    end # end sequence

                    break unless _tmp
                  end
                  _tmp = true
                else
                  self.pos = _save19
                end
                break if _tmp
                self.pos = _save18

                _save24 = self.pos
                while true # sequence
                  _save25 = self.pos
                  _tmp = apply(:_Ticks1)
                  _tmp = _tmp ? nil : true
                  self.pos = _save25
                  unless _tmp
                    self.pos = _save24
                    break
                  end
                  _tmp = scan(/\G(?-mix:`+)/)
                  unless _tmp
                    self.pos = _save24
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save18

                _save26 = self.pos
                while true # sequence
                  _save27 = self.pos

                  _save28 = self.pos
                  while true # sequence
                    _tmp = _Sp()
                    unless _tmp
                      self.pos = _save28
                      break
                    end
                    _tmp = apply(:_Ticks1)
                    unless _tmp
                      self.pos = _save28
                    end
                    break
                  end # end sequence

                  _tmp = _tmp ? nil : true
                  self.pos = _save27
                  unless _tmp
                    self.pos = _save26
                    break
                  end

                  _save29 = self.pos
                  while true # choice
                    _tmp = _Spacechar()
                    break if _tmp
                    self.pos = _save29

                    _save30 = self.pos
                    while true # sequence
                      _tmp = _Newline()
                      unless _tmp
                        self.pos = _save30
                        break
                      end
                      _save31 = self.pos
                      _tmp = _BlankLine()
                      _tmp = _tmp ? nil : true
                      self.pos = _save31
                      unless _tmp
                        self.pos = _save30
                      end
                      break
                    end # end sequence

                    break if _tmp
                    self.pos = _save29
                    break
                  end # end choice

                  unless _tmp
                    self.pos = _save26
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save18
                break
              end # end choice

              break unless _tmp
            end
            _tmp = true
          else
            self.pos = _save3
          end
          if _tmp
            text = get_text(_text_start)
          end
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = apply(:_Ticks1)
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1

        _save32 = self.pos
        while true # sequence
          _tmp = apply(:_Ticks2)
          unless _tmp
            self.pos = _save32
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save32
            break
          end
          _text_start = self.pos
          _save33 = self.pos

          _save34 = self.pos
          while true # choice
            _save35 = self.pos

            _save36 = self.pos
            while true # sequence
              _save37 = self.pos
              _tmp = match_string("`")
              _tmp = _tmp ? nil : true
              self.pos = _save37
              unless _tmp
                self.pos = _save36
                break
              end
              _tmp = apply(:_Nonspacechar)
              unless _tmp
                self.pos = _save36
              end
              break
            end # end sequence

            if _tmp
              while true

                _save38 = self.pos
                while true # sequence
                  _save39 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save39
                  unless _tmp
                    self.pos = _save38
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save38
                  end
                  break
                end # end sequence

                break unless _tmp
              end
              _tmp = true
            else
              self.pos = _save35
            end
            break if _tmp
            self.pos = _save34

            _save40 = self.pos
            while true # sequence
              _save41 = self.pos
              _tmp = apply(:_Ticks2)
              _tmp = _tmp ? nil : true
              self.pos = _save41
              unless _tmp
                self.pos = _save40
                break
              end
              _tmp = scan(/\G(?-mix:`+)/)
              unless _tmp
                self.pos = _save40
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save34

            _save42 = self.pos
            while true # sequence
              _save43 = self.pos

              _save44 = self.pos
              while true # sequence
                _tmp = _Sp()
                unless _tmp
                  self.pos = _save44
                  break
                end
                _tmp = apply(:_Ticks2)
                unless _tmp
                  self.pos = _save44
                end
                break
              end # end sequence

              _tmp = _tmp ? nil : true
              self.pos = _save43
              unless _tmp
                self.pos = _save42
                break
              end

              _save45 = self.pos
              while true # choice
                _tmp = _Spacechar()
                break if _tmp
                self.pos = _save45

                _save46 = self.pos
                while true # sequence
                  _tmp = _Newline()
                  unless _tmp
                    self.pos = _save46
                    break
                  end
                  _save47 = self.pos
                  _tmp = _BlankLine()
                  _tmp = _tmp ? nil : true
                  self.pos = _save47
                  unless _tmp
                    self.pos = _save46
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save45
                break
              end # end choice

              unless _tmp
                self.pos = _save42
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save34
            break
          end # end choice

          if _tmp
            while true

              _save48 = self.pos
              while true # choice
                _save49 = self.pos

                _save50 = self.pos
                while true # sequence
                  _save51 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save51
                  unless _tmp
                    self.pos = _save50
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save50
                  end
                  break
                end # end sequence

                if _tmp
                  while true

                    _save52 = self.pos
                    while true # sequence
                      _save53 = self.pos
                      _tmp = match_string("`")
                      _tmp = _tmp ? nil : true
                      self.pos = _save53
                      unless _tmp
                        self.pos = _save52
                        break
                      end
                      _tmp = apply(:_Nonspacechar)
                      unless _tmp
                        self.pos = _save52
                      end
                      break
                    end # end sequence

                    break unless _tmp
                  end
                  _tmp = true
                else
                  self.pos = _save49
                end
                break if _tmp
                self.pos = _save48

                _save54 = self.pos
                while true # sequence
                  _save55 = self.pos
                  _tmp = apply(:_Ticks2)
                  _tmp = _tmp ? nil : true
                  self.pos = _save55
                  unless _tmp
                    self.pos = _save54
                    break
                  end
                  _tmp = scan(/\G(?-mix:`+)/)
                  unless _tmp
                    self.pos = _save54
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save48

                _save56 = self.pos
                while true # sequence
                  _save57 = self.pos

                  _save58 = self.pos
                  while true # sequence
                    _tmp = _Sp()
                    unless _tmp
                      self.pos = _save58
                      break
                    end
                    _tmp = apply(:_Ticks2)
                    unless _tmp
                      self.pos = _save58
                    end
                    break
                  end # end sequence

                  _tmp = _tmp ? nil : true
                  self.pos = _save57
                  unless _tmp
                    self.pos = _save56
                    break
                  end

                  _save59 = self.pos
                  while true # choice
                    _tmp = _Spacechar()
                    break if _tmp
                    self.pos = _save59

                    _save60 = self.pos
                    while true # sequence
                      _tmp = _Newline()
                      unless _tmp
                        self.pos = _save60
                        break
                      end
                      _save61 = self.pos
                      _tmp = _BlankLine()
                      _tmp = _tmp ? nil : true
                      self.pos = _save61
                      unless _tmp
                        self.pos = _save60
                      end
                      break
                    end # end sequence

                    break if _tmp
                    self.pos = _save59
                    break
                  end # end choice

                  unless _tmp
                    self.pos = _save56
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save48
                break
              end # end choice

              break unless _tmp
            end
            _tmp = true
          else
            self.pos = _save33
          end
          if _tmp
            text = get_text(_text_start)
          end
          unless _tmp
            self.pos = _save32
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save32
            break
          end
          _tmp = apply(:_Ticks2)
          unless _tmp
            self.pos = _save32
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1

        _save62 = self.pos
        while true # sequence
          _tmp = apply(:_Ticks3)
          unless _tmp
            self.pos = _save62
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save62
            break
          end
          _text_start = self.pos
          _save63 = self.pos

          _save64 = self.pos
          while true # choice
            _save65 = self.pos

            _save66 = self.pos
            while true # sequence
              _save67 = self.pos
              _tmp = match_string("`")
              _tmp = _tmp ? nil : true
              self.pos = _save67
              unless _tmp
                self.pos = _save66
                break
              end
              _tmp = apply(:_Nonspacechar)
              unless _tmp
                self.pos = _save66
              end
              break
            end # end sequence

            if _tmp
              while true

                _save68 = self.pos
                while true # sequence
                  _save69 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save69
                  unless _tmp
                    self.pos = _save68
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save68
                  end
                  break
                end # end sequence

                break unless _tmp
              end
              _tmp = true
            else
              self.pos = _save65
            end
            break if _tmp
            self.pos = _save64

            _save70 = self.pos
            while true # sequence
              _save71 = self.pos
              _tmp = apply(:_Ticks3)
              _tmp = _tmp ? nil : true
              self.pos = _save71
              unless _tmp
                self.pos = _save70
                break
              end
              _tmp = scan(/\G(?-mix:`+)/)
              unless _tmp
                self.pos = _save70
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save64

            _save72 = self.pos
            while true # sequence
              _save73 = self.pos

              _save74 = self.pos
              while true # sequence
                _tmp = _Sp()
                unless _tmp
                  self.pos = _save74
                  break
                end
                _tmp = apply(:_Ticks3)
                unless _tmp
                  self.pos = _save74
                end
                break
              end # end sequence

              _tmp = _tmp ? nil : true
              self.pos = _save73
              unless _tmp
                self.pos = _save72
                break
              end

              _save75 = self.pos
              while true # choice
                _tmp = _Spacechar()
                break if _tmp
                self.pos = _save75

                _save76 = self.pos
                while true # sequence
                  _tmp = _Newline()
                  unless _tmp
                    self.pos = _save76
                    break
                  end
                  _save77 = self.pos
                  _tmp = _BlankLine()
                  _tmp = _tmp ? nil : true
                  self.pos = _save77
                  unless _tmp
                    self.pos = _save76
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save75
                break
              end # end choice

              unless _tmp
                self.pos = _save72
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save64
            break
          end # end choice

          if _tmp
            while true

              _save78 = self.pos
              while true # choice
                _save79 = self.pos

                _save80 = self.pos
                while true # sequence
                  _save81 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save81
                  unless _tmp
                    self.pos = _save80
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save80
                  end
                  break
                end # end sequence

                if _tmp
                  while true

                    _save82 = self.pos
                    while true # sequence
                      _save83 = self.pos
                      _tmp = match_string("`")
                      _tmp = _tmp ? nil : true
                      self.pos = _save83
                      unless _tmp
                        self.pos = _save82
                        break
                      end
                      _tmp = apply(:_Nonspacechar)
                      unless _tmp
                        self.pos = _save82
                      end
                      break
                    end # end sequence

                    break unless _tmp
                  end
                  _tmp = true
                else
                  self.pos = _save79
                end
                break if _tmp
                self.pos = _save78

                _save84 = self.pos
                while true # sequence
                  _save85 = self.pos
                  _tmp = apply(:_Ticks3)
                  _tmp = _tmp ? nil : true
                  self.pos = _save85
                  unless _tmp
                    self.pos = _save84
                    break
                  end
                  _tmp = scan(/\G(?-mix:`+)/)
                  unless _tmp
                    self.pos = _save84
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save78

                _save86 = self.pos
                while true # sequence
                  _save87 = self.pos

                  _save88 = self.pos
                  while true # sequence
                    _tmp = _Sp()
                    unless _tmp
                      self.pos = _save88
                      break
                    end
                    _tmp = apply(:_Ticks3)
                    unless _tmp
                      self.pos = _save88
                    end
                    break
                  end # end sequence

                  _tmp = _tmp ? nil : true
                  self.pos = _save87
                  unless _tmp
                    self.pos = _save86
                    break
                  end

                  _save89 = self.pos
                  while true # choice
                    _tmp = _Spacechar()
                    break if _tmp
                    self.pos = _save89

                    _save90 = self.pos
                    while true # sequence
                      _tmp = _Newline()
                      unless _tmp
                        self.pos = _save90
                        break
                      end
                      _save91 = self.pos
                      _tmp = _BlankLine()
                      _tmp = _tmp ? nil : true
                      self.pos = _save91
                      unless _tmp
                        self.pos = _save90
                      end
                      break
                    end # end sequence

                    break if _tmp
                    self.pos = _save89
                    break
                  end # end choice

                  unless _tmp
                    self.pos = _save86
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save78
                break
              end # end choice

              break unless _tmp
            end
            _tmp = true
          else
            self.pos = _save63
          end
          if _tmp
            text = get_text(_text_start)
          end
          unless _tmp
            self.pos = _save62
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save62
            break
          end
          _tmp = apply(:_Ticks3)
          unless _tmp
            self.pos = _save62
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1

        _save92 = self.pos
        while true # sequence
          _tmp = apply(:_Ticks4)
          unless _tmp
            self.pos = _save92
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save92
            break
          end
          _text_start = self.pos
          _save93 = self.pos

          _save94 = self.pos
          while true # choice
            _save95 = self.pos

            _save96 = self.pos
            while true # sequence
              _save97 = self.pos
              _tmp = match_string("`")
              _tmp = _tmp ? nil : true
              self.pos = _save97
              unless _tmp
                self.pos = _save96
                break
              end
              _tmp = apply(:_Nonspacechar)
              unless _tmp
                self.pos = _save96
              end
              break
            end # end sequence

            if _tmp
              while true

                _save98 = self.pos
                while true # sequence
                  _save99 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save99
                  unless _tmp
                    self.pos = _save98
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save98
                  end
                  break
                end # end sequence

                break unless _tmp
              end
              _tmp = true
            else
              self.pos = _save95
            end
            break if _tmp
            self.pos = _save94

            _save100 = self.pos
            while true # sequence
              _save101 = self.pos
              _tmp = apply(:_Ticks4)
              _tmp = _tmp ? nil : true
              self.pos = _save101
              unless _tmp
                self.pos = _save100
                break
              end
              _tmp = scan(/\G(?-mix:`+)/)
              unless _tmp
                self.pos = _save100
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save94

            _save102 = self.pos
            while true # sequence
              _save103 = self.pos

              _save104 = self.pos
              while true # sequence
                _tmp = _Sp()
                unless _tmp
                  self.pos = _save104
                  break
                end
                _tmp = apply(:_Ticks4)
                unless _tmp
                  self.pos = _save104
                end
                break
              end # end sequence

              _tmp = _tmp ? nil : true
              self.pos = _save103
              unless _tmp
                self.pos = _save102
                break
              end

              _save105 = self.pos
              while true # choice
                _tmp = _Spacechar()
                break if _tmp
                self.pos = _save105

                _save106 = self.pos
                while true # sequence
                  _tmp = _Newline()
                  unless _tmp
                    self.pos = _save106
                    break
                  end
                  _save107 = self.pos
                  _tmp = _BlankLine()
                  _tmp = _tmp ? nil : true
                  self.pos = _save107
                  unless _tmp
                    self.pos = _save106
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save105
                break
              end # end choice

              unless _tmp
                self.pos = _save102
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save94
            break
          end # end choice

          if _tmp
            while true

              _save108 = self.pos
              while true # choice
                _save109 = self.pos

                _save110 = self.pos
                while true # sequence
                  _save111 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save111
                  unless _tmp
                    self.pos = _save110
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save110
                  end
                  break
                end # end sequence

                if _tmp
                  while true

                    _save112 = self.pos
                    while true # sequence
                      _save113 = self.pos
                      _tmp = match_string("`")
                      _tmp = _tmp ? nil : true
                      self.pos = _save113
                      unless _tmp
                        self.pos = _save112
                        break
                      end
                      _tmp = apply(:_Nonspacechar)
                      unless _tmp
                        self.pos = _save112
                      end
                      break
                    end # end sequence

                    break unless _tmp
                  end
                  _tmp = true
                else
                  self.pos = _save109
                end
                break if _tmp
                self.pos = _save108

                _save114 = self.pos
                while true # sequence
                  _save115 = self.pos
                  _tmp = apply(:_Ticks4)
                  _tmp = _tmp ? nil : true
                  self.pos = _save115
                  unless _tmp
                    self.pos = _save114
                    break
                  end
                  _tmp = scan(/\G(?-mix:`+)/)
                  unless _tmp
                    self.pos = _save114
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save108

                _save116 = self.pos
                while true # sequence
                  _save117 = self.pos

                  _save118 = self.pos
                  while true # sequence
                    _tmp = _Sp()
                    unless _tmp
                      self.pos = _save118
                      break
                    end
                    _tmp = apply(:_Ticks4)
                    unless _tmp
                      self.pos = _save118
                    end
                    break
                  end # end sequence

                  _tmp = _tmp ? nil : true
                  self.pos = _save117
                  unless _tmp
                    self.pos = _save116
                    break
                  end

                  _save119 = self.pos
                  while true # choice
                    _tmp = _Spacechar()
                    break if _tmp
                    self.pos = _save119

                    _save120 = self.pos
                    while true # sequence
                      _tmp = _Newline()
                      unless _tmp
                        self.pos = _save120
                        break
                      end
                      _save121 = self.pos
                      _tmp = _BlankLine()
                      _tmp = _tmp ? nil : true
                      self.pos = _save121
                      unless _tmp
                        self.pos = _save120
                      end
                      break
                    end # end sequence

                    break if _tmp
                    self.pos = _save119
                    break
                  end # end choice

                  unless _tmp
                    self.pos = _save116
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save108
                break
              end # end choice

              break unless _tmp
            end
            _tmp = true
          else
            self.pos = _save93
          end
          if _tmp
            text = get_text(_text_start)
          end
          unless _tmp
            self.pos = _save92
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save92
            break
          end
          _tmp = apply(:_Ticks4)
          unless _tmp
            self.pos = _save92
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1

        _save122 = self.pos
        while true # sequence
          _tmp = apply(:_Ticks5)
          unless _tmp
            self.pos = _save122
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save122
            break
          end
          _text_start = self.pos
          _save123 = self.pos

          _save124 = self.pos
          while true # choice
            _save125 = self.pos

            _save126 = self.pos
            while true # sequence
              _save127 = self.pos
              _tmp = match_string("`")
              _tmp = _tmp ? nil : true
              self.pos = _save127
              unless _tmp
                self.pos = _save126
                break
              end
              _tmp = apply(:_Nonspacechar)
              unless _tmp
                self.pos = _save126
              end
              break
            end # end sequence

            if _tmp
              while true

                _save128 = self.pos
                while true # sequence
                  _save129 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save129
                  unless _tmp
                    self.pos = _save128
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save128
                  end
                  break
                end # end sequence

                break unless _tmp
              end
              _tmp = true
            else
              self.pos = _save125
            end
            break if _tmp
            self.pos = _save124

            _save130 = self.pos
            while true # sequence
              _save131 = self.pos
              _tmp = apply(:_Ticks5)
              _tmp = _tmp ? nil : true
              self.pos = _save131
              unless _tmp
                self.pos = _save130
                break
              end
              _tmp = scan(/\G(?-mix:`+)/)
              unless _tmp
                self.pos = _save130
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save124

            _save132 = self.pos
            while true # sequence
              _save133 = self.pos

              _save134 = self.pos
              while true # sequence
                _tmp = _Sp()
                unless _tmp
                  self.pos = _save134
                  break
                end
                _tmp = apply(:_Ticks5)
                unless _tmp
                  self.pos = _save134
                end
                break
              end # end sequence

              _tmp = _tmp ? nil : true
              self.pos = _save133
              unless _tmp
                self.pos = _save132
                break
              end

              _save135 = self.pos
              while true # choice
                _tmp = _Spacechar()
                break if _tmp
                self.pos = _save135

                _save136 = self.pos
                while true # sequence
                  _tmp = _Newline()
                  unless _tmp
                    self.pos = _save136
                    break
                  end
                  _save137 = self.pos
                  _tmp = _BlankLine()
                  _tmp = _tmp ? nil : true
                  self.pos = _save137
                  unless _tmp
                    self.pos = _save136
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save135
                break
              end # end choice

              unless _tmp
                self.pos = _save132
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save124
            break
          end # end choice

          if _tmp
            while true

              _save138 = self.pos
              while true # choice
                _save139 = self.pos

                _save140 = self.pos
                while true # sequence
                  _save141 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save141
                  unless _tmp
                    self.pos = _save140
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save140
                  end
                  break
                end # end sequence

                if _tmp
                  while true

                    _save142 = self.pos
                    while true # sequence
                      _save143 = self.pos
                      _tmp = match_string("`")
                      _tmp = _tmp ? nil : true
                      self.pos = _save143
                      unless _tmp
                        self.pos = _save142
                        break
                      end
                      _tmp = apply(:_Nonspacechar)
                      unless _tmp
                        self.pos = _save142
                      end
                      break
                    end # end sequence

                    break unless _tmp
                  end
                  _tmp = true
                else
                  self.pos = _save139
                end
                break if _tmp
                self.pos = _save138

                _save144 = self.pos
                while true # sequence
                  _save145 = self.pos
                  _tmp = apply(:_Ticks5)
                  _tmp = _tmp ? nil : true
                  self.pos = _save145
                  unless _tmp
                    self.pos = _save144
                    break
                  end
                  _tmp = scan(/\G(?-mix:`+)/)
                  unless _tmp
                    self.pos = _save144
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save138

                _save146 = self.pos
                while true # sequence
                  _save147 = self.pos

                  _save148 = self.pos
                  while true # sequence
                    _tmp = _Sp()
                    unless _tmp
                      self.pos = _save148
                      break
                    end
                    _tmp = apply(:_Ticks5)
                    unless _tmp
                      self.pos = _save148
                    end
                    break
                  end # end sequence

                  _tmp = _tmp ? nil : true
                  self.pos = _save147
                  unless _tmp
                    self.pos = _save146
                    break
                  end

                  _save149 = self.pos
                  while true # choice
                    _tmp = _Spacechar()
                    break if _tmp
                    self.pos = _save149

                    _save150 = self.pos
                    while true # sequence
                      _tmp = _Newline()
                      unless _tmp
                        self.pos = _save150
                        break
                      end
                      _save151 = self.pos
                      _tmp = _BlankLine()
                      _tmp = _tmp ? nil : true
                      self.pos = _save151
                      unless _tmp
                        self.pos = _save150
                      end
                      break
                    end # end sequence

                    break if _tmp
                    self.pos = _save149
                    break
                  end # end choice

                  unless _tmp
                    self.pos = _save146
                  end
                  break
                end # end sequence

                break if _tmp
                self.pos = _save138
                break
              end # end choice

              break unless _tmp
            end
            _tmp = true
          else
            self.pos = _save123
          end
          if _tmp
            text = get_text(_text_start)
          end
          unless _tmp
            self.pos = _save122
            break
          end
          _tmp = _Sp()
          unless _tmp
            self.pos = _save122
            break
          end
          _tmp = apply(:_Ticks5)
          unless _tmp
            self.pos = _save122
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  "<code>#{text}</code>" ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Code unless _tmp
    return _tmp
  end

  # RawHtml = < (HtmlComment | HtmlBlockScript | HtmlTag) > { if html? then text else '' end }
  def _RawHtml

    _save = self.pos
    while true # sequence
      _text_start = self.pos

      _save1 = self.pos
      while true # choice
        _tmp = apply(:_HtmlComment)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_HtmlBlockScript)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_HtmlTag)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  if html? then text else '' end ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_RawHtml unless _tmp
    return _tmp
  end

  # BlankLine = @Sp @Newline { "\n" }
  def _BlankLine

    _save = self.pos
    while true # sequence
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  "\n" ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_BlankLine unless _tmp
    return _tmp
  end

  # Quoted = ("\"" (!"\"" .)* "\"" | "'" (!"'" .)* "'")
  def _Quoted

    _save = self.pos
    while true # choice

      _save1 = self.pos
      while true # sequence
        _tmp = match_string("\"")
        unless _tmp
          self.pos = _save1
          break
        end
        while true

          _save3 = self.pos
          while true # sequence
            _save4 = self.pos
            _tmp = match_string("\"")
            _tmp = _tmp ? nil : true
            self.pos = _save4
            unless _tmp
              self.pos = _save3
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save3
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
        unless _tmp
          self.pos = _save1
          break
        end
        _tmp = match_string("\"")
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save

      _save5 = self.pos
      while true # sequence
        _tmp = match_string("'")
        unless _tmp
          self.pos = _save5
          break
        end
        while true

          _save7 = self.pos
          while true # sequence
            _save8 = self.pos
            _tmp = match_string("'")
            _tmp = _tmp ? nil : true
            self.pos = _save8
            unless _tmp
              self.pos = _save7
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save7
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
        unless _tmp
          self.pos = _save5
          break
        end
        _tmp = match_string("'")
        unless _tmp
          self.pos = _save5
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_Quoted unless _tmp
    return _tmp
  end

  # HtmlAttribute = (AlphanumericAscii | "-")+ Spnl ("=" Spnl (Quoted | (!">" Nonspacechar)+))? Spnl
  def _HtmlAttribute

    _save = self.pos
    while true # sequence
      _save1 = self.pos

      _save2 = self.pos
      while true # choice
        _tmp = apply(:_AlphanumericAscii)
        break if _tmp
        self.pos = _save2
        _tmp = match_string("-")
        break if _tmp
        self.pos = _save2
        break
      end # end choice

      if _tmp
        while true

          _save3 = self.pos
          while true # choice
            _tmp = apply(:_AlphanumericAscii)
            break if _tmp
            self.pos = _save3
            _tmp = match_string("-")
            break if _tmp
            self.pos = _save3
            break
          end # end choice

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _save4 = self.pos

      _save5 = self.pos
      while true # sequence
        _tmp = match_string("=")
        unless _tmp
          self.pos = _save5
          break
        end
        _tmp = apply(:_Spnl)
        unless _tmp
          self.pos = _save5
          break
        end

        _save6 = self.pos
        while true # choice
          _tmp = apply(:_Quoted)
          break if _tmp
          self.pos = _save6
          _save7 = self.pos

          _save8 = self.pos
          while true # sequence
            _save9 = self.pos
            _tmp = match_string(">")
            _tmp = _tmp ? nil : true
            self.pos = _save9
            unless _tmp
              self.pos = _save8
              break
            end
            _tmp = apply(:_Nonspacechar)
            unless _tmp
              self.pos = _save8
            end
            break
          end # end sequence

          if _tmp
            while true

              _save10 = self.pos
              while true # sequence
                _save11 = self.pos
                _tmp = match_string(">")
                _tmp = _tmp ? nil : true
                self.pos = _save11
                unless _tmp
                  self.pos = _save10
                  break
                end
                _tmp = apply(:_Nonspacechar)
                unless _tmp
                  self.pos = _save10
                end
                break
              end # end sequence

              break unless _tmp
            end
            _tmp = true
          else
            self.pos = _save7
          end
          break if _tmp
          self.pos = _save6
          break
        end # end choice

        unless _tmp
          self.pos = _save5
        end
        break
      end # end sequence

      unless _tmp
        _tmp = true
        self.pos = _save4
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlAttribute unless _tmp
    return _tmp
  end

  # HtmlComment = "<!--" (!"-->" .)* "-->"
  def _HtmlComment

    _save = self.pos
    while true # sequence
      _tmp = match_string("<!--")
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos
          _tmp = match_string("-->")
          _tmp = _tmp ? nil : true
          self.pos = _save3
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = get_byte
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("-->")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlComment unless _tmp
    return _tmp
  end

  # HtmlTag = "<" Spnl "/"? AlphanumericAscii+ Spnl HtmlAttribute* "/"? Spnl ">"
  def _HtmlTag

    _save = self.pos
    while true # sequence
      _tmp = match_string("<")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = match_string("/")
      unless _tmp
        _tmp = true
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _tmp = apply(:_AlphanumericAscii)
      if _tmp
        while true
          _tmp = apply(:_AlphanumericAscii)
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = apply(:_HtmlAttribute)
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      _save4 = self.pos
      _tmp = match_string("/")
      unless _tmp
        _tmp = true
        self.pos = _save4
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(">")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HtmlTag unless _tmp
    return _tmp
  end

  # Eof = !.
  def _Eof
    _save = self.pos
    _tmp = get_byte
    _tmp = _tmp ? nil : true
    self.pos = _save
    set_failed_rule :_Eof unless _tmp
    return _tmp
  end

  # Nonspacechar = !@Spacechar !@Newline .
  def _Nonspacechar

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = _Spacechar()
      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _tmp = _Newline()
      _tmp = _tmp ? nil : true
      self.pos = _save2
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = get_byte
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Nonspacechar unless _tmp
    return _tmp
  end

  # Sp = @Spacechar*
  def _Sp
    while true
      _tmp = _Spacechar()
      break unless _tmp
    end
    _tmp = true
    set_failed_rule :_Sp unless _tmp
    return _tmp
  end

  # Spnl = @Sp (@Newline @Sp)?
  def _Spnl

    _save = self.pos
    while true # sequence
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos

      _save2 = self.pos
      while true # sequence
        _tmp = _Newline()
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = _Sp()
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      unless _tmp
        _tmp = true
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Spnl unless _tmp
    return _tmp
  end

  # SpecialChar = (/[~*_`&\[\]()<!#\\'"]/ | @ExtendedSpecialChar)
  def _SpecialChar

    _save = self.pos
    while true # choice
      _tmp = scan(/\G(?-mix:[~*_`&\[\]()<!#\\'"])/)
      break if _tmp
      self.pos = _save
      _tmp = _ExtendedSpecialChar()
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_SpecialChar unless _tmp
    return _tmp
  end

  # NormalChar = !(@SpecialChar | @Spacechar | @Newline) .
  def _NormalChar

    _save = self.pos
    while true # sequence
      _save1 = self.pos

      _save2 = self.pos
      while true # choice
        _tmp = _SpecialChar()
        break if _tmp
        self.pos = _save2
        _tmp = _Spacechar()
        break if _tmp
        self.pos = _save2
        _tmp = _Newline()
        break if _tmp
        self.pos = _save2
        break
      end # end choice

      _tmp = _tmp ? nil : true
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = get_byte
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_NormalChar unless _tmp
    return _tmp
  end

  # Digit = [0-9]
  def _Digit
    _save = self.pos
    _tmp = get_byte
    if _tmp
      unless _tmp >= 48 and _tmp <= 57
        self.pos = _save
        _tmp = nil
      end
    end
    set_failed_rule :_Digit unless _tmp
    return _tmp
  end

  # Alphanumeric = %literals.Alphanumeric
  def _Alphanumeric
    _tmp = @_grammar_literals.external_invoke(self, :_Alphanumeric)
    set_failed_rule :_Alphanumeric unless _tmp
    return _tmp
  end

  # AlphanumericAscii = %literals.AlphanumericAscii
  def _AlphanumericAscii
    _tmp = @_grammar_literals.external_invoke(self, :_AlphanumericAscii)
    set_failed_rule :_AlphanumericAscii unless _tmp
    return _tmp
  end

  # BOM = %literals.BOM
  def _BOM
    _tmp = @_grammar_literals.external_invoke(self, :_BOM)
    set_failed_rule :_BOM unless _tmp
    return _tmp
  end

  # Newline = %literals.Newline
  def _Newline
    _tmp = @_grammar_literals.external_invoke(self, :_Newline)
    set_failed_rule :_Newline unless _tmp
    return _tmp
  end

  # Spacechar = %literals.Spacechar
  def _Spacechar
    _tmp = @_grammar_literals.external_invoke(self, :_Spacechar)
    set_failed_rule :_Spacechar unless _tmp
    return _tmp
  end

  # HexEntity = /&#x/i < /[0-9a-fA-F]+/ > ";" { [text.to_i(16)].pack 'U' }
  def _HexEntity

    _save = self.pos
    while true # sequence
      _tmp = scan(/\G(?i-mx:&#x)/)
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _tmp = scan(/\G(?-mix:[0-9a-fA-F]+)/)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(";")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  [text.to_i(16)].pack 'U' ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_HexEntity unless _tmp
    return _tmp
  end

  # DecEntity = "&#" < /[0-9]+/ > ";" { [text.to_i].pack 'U' }
  def _DecEntity

    _save = self.pos
    while true # sequence
      _tmp = match_string("&#")
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _tmp = scan(/\G(?-mix:[0-9]+)/)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(";")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  [text.to_i].pack 'U' ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_DecEntity unless _tmp
    return _tmp
  end

  # CharEntity = "&" < /[A-Za-z0-9]+/ > ";" { if entity = HTML_ENTITIES[text] then                  entity.pack 'U*'                else                  "&#{text};"                end              }
  def _CharEntity

    _save = self.pos
    while true # sequence
      _tmp = match_string("&")
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _tmp = scan(/\G(?-mix:[A-Za-z0-9]+)/)
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(";")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  if entity = HTML_ENTITIES[text] then
                 entity.pack 'U*'
               else
                 "&#{text};"
               end
             ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_CharEntity unless _tmp
    return _tmp
  end

  # NonindentSpace = / {0,3}/
  def _NonindentSpace
    _tmp = scan(/\G(?-mix: {0,3})/)
    set_failed_rule :_NonindentSpace unless _tmp
    return _tmp
  end

  # Indent = /\t|    /
  def _Indent
    _tmp = scan(/\G(?-mix:\t|    )/)
    set_failed_rule :_Indent unless _tmp
    return _tmp
  end

  # IndentedLine = Indent Line
  def _IndentedLine

    _save = self.pos
    while true # sequence
      _tmp = apply(:_Indent)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Line)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_IndentedLine unless _tmp
    return _tmp
  end

  # OptionallyIndentedLine = Indent? Line
  def _OptionallyIndentedLine

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = apply(:_Indent)
      unless _tmp
        _tmp = true
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Line)
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_OptionallyIndentedLine unless _tmp
    return _tmp
  end

  # StartList = &. { [] }
  def _StartList

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = get_byte
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  [] ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_StartList unless _tmp
    return _tmp
  end

  # Line = @RawLine:a { a }
  def _Line

    _save = self.pos
    while true # sequence
      _tmp = _RawLine()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Line unless _tmp
    return _tmp
  end

  # RawLine = (< (!"\r" !"\n" .)* @Newline > | < .+ > @Eof) { text }
  def _RawLine

    _save = self.pos
    while true # sequence

      _save1 = self.pos
      while true # choice
        _text_start = self.pos

        _save2 = self.pos
        while true # sequence
          while true

            _save4 = self.pos
            while true # sequence
              _save5 = self.pos
              _tmp = match_string("\r")
              _tmp = _tmp ? nil : true
              self.pos = _save5
              unless _tmp
                self.pos = _save4
                break
              end
              _save6 = self.pos
              _tmp = match_string("\n")
              _tmp = _tmp ? nil : true
              self.pos = _save6
              unless _tmp
                self.pos = _save4
                break
              end
              _tmp = get_byte
              unless _tmp
                self.pos = _save4
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
          unless _tmp
            self.pos = _save2
            break
          end
          _tmp = _Newline()
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        if _tmp
          text = get_text(_text_start)
        end
        break if _tmp
        self.pos = _save1

        _save7 = self.pos
        while true # sequence
          _text_start = self.pos
          _save8 = self.pos
          _tmp = get_byte
          if _tmp
            while true
              _tmp = get_byte
              break unless _tmp
            end
            _tmp = true
          else
            self.pos = _save8
          end
          if _tmp
            text = get_text(_text_start)
          end
          unless _tmp
            self.pos = _save7
            break
          end
          _tmp = _Eof()
          unless _tmp
            self.pos = _save7
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1
        break
      end # end choice

      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_RawLine unless _tmp
    return _tmp
  end

  # SkipBlock = (HtmlBlock | (!"#" !SetextBottom1 !SetextBottom2 !@BlankLine @RawLine)+ @BlankLine* | @BlankLine+ | @RawLine)
  def _SkipBlock

    _save = self.pos
    while true # choice
      _tmp = apply(:_HtmlBlock)
      break if _tmp
      self.pos = _save

      _save1 = self.pos
      while true # sequence
        _save2 = self.pos

        _save3 = self.pos
        while true # sequence
          _save4 = self.pos
          _tmp = match_string("#")
          _tmp = _tmp ? nil : true
          self.pos = _save4
          unless _tmp
            self.pos = _save3
            break
          end
          _save5 = self.pos
          _tmp = apply(:_SetextBottom1)
          _tmp = _tmp ? nil : true
          self.pos = _save5
          unless _tmp
            self.pos = _save3
            break
          end
          _save6 = self.pos
          _tmp = apply(:_SetextBottom2)
          _tmp = _tmp ? nil : true
          self.pos = _save6
          unless _tmp
            self.pos = _save3
            break
          end
          _save7 = self.pos
          _tmp = _BlankLine()
          _tmp = _tmp ? nil : true
          self.pos = _save7
          unless _tmp
            self.pos = _save3
            break
          end
          _tmp = _RawLine()
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        if _tmp
          while true

            _save8 = self.pos
            while true # sequence
              _save9 = self.pos
              _tmp = match_string("#")
              _tmp = _tmp ? nil : true
              self.pos = _save9
              unless _tmp
                self.pos = _save8
                break
              end
              _save10 = self.pos
              _tmp = apply(:_SetextBottom1)
              _tmp = _tmp ? nil : true
              self.pos = _save10
              unless _tmp
                self.pos = _save8
                break
              end
              _save11 = self.pos
              _tmp = apply(:_SetextBottom2)
              _tmp = _tmp ? nil : true
              self.pos = _save11
              unless _tmp
                self.pos = _save8
                break
              end
              _save12 = self.pos
              _tmp = _BlankLine()
              _tmp = _tmp ? nil : true
              self.pos = _save12
              unless _tmp
                self.pos = _save8
                break
              end
              _tmp = _RawLine()
              unless _tmp
                self.pos = _save8
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
        else
          self.pos = _save2
        end
        unless _tmp
          self.pos = _save1
          break
        end
        while true
          _tmp = _BlankLine()
          break unless _tmp
        end
        _tmp = true
        unless _tmp
          self.pos = _save1
        end
        break
      end # end sequence

      break if _tmp
      self.pos = _save
      _save14 = self.pos
      _tmp = _BlankLine()
      if _tmp
        while true
          _tmp = _BlankLine()
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save14
      end
      break if _tmp
      self.pos = _save
      _tmp = _RawLine()
      break if _tmp
      self.pos = _save
      break
    end # end choice

    set_failed_rule :_SkipBlock unless _tmp
    return _tmp
  end

  # ExtendedSpecialChar = &{ notes? } "^"
  def _ExtendedSpecialChar

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = begin;  notes? ; end
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("^")
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_ExtendedSpecialChar unless _tmp
    return _tmp
  end

  # NoteReference = &{ notes? } RawNoteReference:ref { note_for ref }
  def _NoteReference

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = begin;  notes? ; end
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_RawNoteReference)
      ref = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  note_for ref ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_NoteReference unless _tmp
    return _tmp
  end

  # RawNoteReference = "[^" < (!@Newline !"]" .)+ > "]" { text }
  def _RawNoteReference

    _save = self.pos
    while true # sequence
      _tmp = match_string("[^")
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _save1 = self.pos

      _save2 = self.pos
      while true # sequence
        _save3 = self.pos
        _tmp = _Newline()
        _tmp = _tmp ? nil : true
        self.pos = _save3
        unless _tmp
          self.pos = _save2
          break
        end
        _save4 = self.pos
        _tmp = match_string("]")
        _tmp = _tmp ? nil : true
        self.pos = _save4
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = get_byte
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      if _tmp
        while true

          _save5 = self.pos
          while true # sequence
            _save6 = self.pos
            _tmp = _Newline()
            _tmp = _tmp ? nil : true
            self.pos = _save6
            unless _tmp
              self.pos = _save5
              break
            end
            _save7 = self.pos
            _tmp = match_string("]")
            _tmp = _tmp ? nil : true
            self.pos = _save7
            unless _tmp
              self.pos = _save5
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save5
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("]")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_RawNoteReference unless _tmp
    return _tmp
  end

  # Note = &{ notes? } @NonindentSpace RawNoteReference:ref ":" @Sp @StartList:a RawNoteBlock:i { a.concat i } (&Indent RawNoteBlock:i { a.concat i })* { @footnotes[ref] = paragraph a                    nil                 }
  def _Note

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = begin;  notes? ; end
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _NonindentSpace()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_RawNoteReference)
      ref = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(":")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_RawNoteBlock)
      i = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a.concat i ; end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      while true

        _save3 = self.pos
        while true # sequence
          _save4 = self.pos
          _tmp = apply(:_Indent)
          self.pos = _save4
          unless _tmp
            self.pos = _save3
            break
          end
          _tmp = apply(:_RawNoteBlock)
          i = @result
          unless _tmp
            self.pos = _save3
            break
          end
          @result = begin;  a.concat i ; end
          _tmp = true
          unless _tmp
            self.pos = _save3
          end
          break
        end # end sequence

        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  @footnotes[ref] = paragraph a

                  nil
                ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Note unless _tmp
    return _tmp
  end

  # InlineNote = &{ notes? } "^[" @StartList:a (!"]" Inline:l { a << l })+ "]" { ref = [:inline, @note_order.length]                @footnotes[ref] = paragraph a                 note_for ref              }
  def _InlineNote

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = begin;  notes? ; end
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("^[")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos

      _save3 = self.pos
      while true # sequence
        _save4 = self.pos
        _tmp = match_string("]")
        _tmp = _tmp ? nil : true
        self.pos = _save4
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = apply(:_Inline)
        l = @result
        unless _tmp
          self.pos = _save3
          break
        end
        @result = begin;  a << l ; end
        _tmp = true
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      if _tmp
        while true

          _save5 = self.pos
          while true # sequence
            _save6 = self.pos
            _tmp = match_string("]")
            _tmp = _tmp ? nil : true
            self.pos = _save6
            unless _tmp
              self.pos = _save5
              break
            end
            _tmp = apply(:_Inline)
            l = @result
            unless _tmp
              self.pos = _save5
              break
            end
            @result = begin;  a << l ; end
            _tmp = true
            unless _tmp
              self.pos = _save5
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("]")
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  ref = [:inline, @note_order.length]
               @footnotes[ref] = paragraph a

               note_for ref
             ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_InlineNote unless _tmp
    return _tmp
  end

  # Notes = (Note | SkipBlock)*
  def _Notes
    while true

      _save1 = self.pos
      while true # choice
        _tmp = apply(:_Note)
        break if _tmp
        self.pos = _save1
        _tmp = apply(:_SkipBlock)
        break if _tmp
        self.pos = _save1
        break
      end # end choice

      break unless _tmp
    end
    _tmp = true
    set_failed_rule :_Notes unless _tmp
    return _tmp
  end

  # RawNoteBlock = @StartList:a (!@BlankLine OptionallyIndentedLine:l { a << l })+ < @BlankLine* > { a << text } { a }
  def _RawNoteBlock

    _save = self.pos
    while true # sequence
      _tmp = _StartList()
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos

      _save2 = self.pos
      while true # sequence
        _save3 = self.pos
        _tmp = _BlankLine()
        _tmp = _tmp ? nil : true
        self.pos = _save3
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = apply(:_OptionallyIndentedLine)
        l = @result
        unless _tmp
          self.pos = _save2
          break
        end
        @result = begin;  a << l ; end
        _tmp = true
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      if _tmp
        while true

          _save4 = self.pos
          while true # sequence
            _save5 = self.pos
            _tmp = _BlankLine()
            _tmp = _tmp ? nil : true
            self.pos = _save5
            unless _tmp
              self.pos = _save4
              break
            end
            _tmp = apply(:_OptionallyIndentedLine)
            l = @result
            unless _tmp
              self.pos = _save4
              break
            end
            @result = begin;  a << l ; end
            _tmp = true
            unless _tmp
              self.pos = _save4
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      while true
        _tmp = _BlankLine()
        break unless _tmp
      end
      _tmp = true
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a << text ; end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_RawNoteBlock unless _tmp
    return _tmp
  end

  # CodeFence = &{ github? } Ticks3 (@Sp StrChunk:format)? Spnl < ((!"`" Nonspacechar)+ | !Ticks3 /`+/ | Spacechar | @Newline)+ > Ticks3 @Sp @Newline* { verbatim = RDoc::Markup::Verbatim.new text               verbatim.format = format.intern if format.instance_of?(String)               verbatim             }
  def _CodeFence

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = begin;  github? ; end
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Ticks3)
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos

      _save3 = self.pos
      while true # sequence
        _tmp = _Sp()
        unless _tmp
          self.pos = _save3
          break
        end
        _tmp = apply(:_StrChunk)
        format = @result
        unless _tmp
          self.pos = _save3
        end
        break
      end # end sequence

      unless _tmp
        _tmp = true
        self.pos = _save2
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Spnl)
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _save4 = self.pos

      _save5 = self.pos
      while true # choice
        _save6 = self.pos

        _save7 = self.pos
        while true # sequence
          _save8 = self.pos
          _tmp = match_string("`")
          _tmp = _tmp ? nil : true
          self.pos = _save8
          unless _tmp
            self.pos = _save7
            break
          end
          _tmp = apply(:_Nonspacechar)
          unless _tmp
            self.pos = _save7
          end
          break
        end # end sequence

        if _tmp
          while true

            _save9 = self.pos
            while true # sequence
              _save10 = self.pos
              _tmp = match_string("`")
              _tmp = _tmp ? nil : true
              self.pos = _save10
              unless _tmp
                self.pos = _save9
                break
              end
              _tmp = apply(:_Nonspacechar)
              unless _tmp
                self.pos = _save9
              end
              break
            end # end sequence

            break unless _tmp
          end
          _tmp = true
        else
          self.pos = _save6
        end
        break if _tmp
        self.pos = _save5

        _save11 = self.pos
        while true # sequence
          _save12 = self.pos
          _tmp = apply(:_Ticks3)
          _tmp = _tmp ? nil : true
          self.pos = _save12
          unless _tmp
            self.pos = _save11
            break
          end
          _tmp = scan(/\G(?-mix:`+)/)
          unless _tmp
            self.pos = _save11
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save5
        _tmp = apply(:_Spacechar)
        break if _tmp
        self.pos = _save5
        _tmp = _Newline()
        break if _tmp
        self.pos = _save5
        break
      end # end choice

      if _tmp
        while true

          _save13 = self.pos
          while true # choice
            _save14 = self.pos

            _save15 = self.pos
            while true # sequence
              _save16 = self.pos
              _tmp = match_string("`")
              _tmp = _tmp ? nil : true
              self.pos = _save16
              unless _tmp
                self.pos = _save15
                break
              end
              _tmp = apply(:_Nonspacechar)
              unless _tmp
                self.pos = _save15
              end
              break
            end # end sequence

            if _tmp
              while true

                _save17 = self.pos
                while true # sequence
                  _save18 = self.pos
                  _tmp = match_string("`")
                  _tmp = _tmp ? nil : true
                  self.pos = _save18
                  unless _tmp
                    self.pos = _save17
                    break
                  end
                  _tmp = apply(:_Nonspacechar)
                  unless _tmp
                    self.pos = _save17
                  end
                  break
                end # end sequence

                break unless _tmp
              end
              _tmp = true
            else
              self.pos = _save14
            end
            break if _tmp
            self.pos = _save13

            _save19 = self.pos
            while true # sequence
              _save20 = self.pos
              _tmp = apply(:_Ticks3)
              _tmp = _tmp ? nil : true
              self.pos = _save20
              unless _tmp
                self.pos = _save19
                break
              end
              _tmp = scan(/\G(?-mix:`+)/)
              unless _tmp
                self.pos = _save19
              end
              break
            end # end sequence

            break if _tmp
            self.pos = _save13
            _tmp = apply(:_Spacechar)
            break if _tmp
            self.pos = _save13
            _tmp = _Newline()
            break if _tmp
            self.pos = _save13
            break
          end # end choice

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save4
      end
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Ticks3)
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      while true
        _tmp = _Newline()
        break unless _tmp
      end
      _tmp = true
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  verbatim = RDoc::Markup::Verbatim.new text
              verbatim.format = format.intern if format.instance_of?(String)
              verbatim
            ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_CodeFence unless _tmp
    return _tmp
  end

  # Table = &{ github? } TableRow:header TableLine:line TableRow+:body { table = RDoc::Markup::Table.new(header, line, body) }
  def _Table

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = begin;  github? ; end
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_TableRow)
      header = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_TableLine)
      line = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _ary = []
      _tmp = apply(:_TableRow)
      if _tmp
        _ary << @result
        while true
          _tmp = apply(:_TableRow)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save2
      end
      body = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  table = RDoc::Markup::Table.new(header, line, body) ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_Table unless _tmp
    return _tmp
  end

  # TableRow = TableItem+:row "|" @Newline { row }
  def _TableRow

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _ary = []
      _tmp = apply(:_TableItem)
      if _tmp
        _ary << @result
        while true
          _tmp = apply(:_TableItem)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save1
      end
      row = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("|")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  row ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_TableRow unless _tmp
    return _tmp
  end

  # TableItem = "|" < (!"|" !@Newline .)+ > { text.strip }
  def _TableItem

    _save = self.pos
    while true # sequence
      _tmp = match_string("|")
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos
      _save1 = self.pos

      _save2 = self.pos
      while true # sequence
        _save3 = self.pos
        _tmp = match_string("|")
        _tmp = _tmp ? nil : true
        self.pos = _save3
        unless _tmp
          self.pos = _save2
          break
        end
        _save4 = self.pos
        _tmp = _Newline()
        _tmp = _tmp ? nil : true
        self.pos = _save4
        unless _tmp
          self.pos = _save2
          break
        end
        _tmp = get_byte
        unless _tmp
          self.pos = _save2
        end
        break
      end # end sequence

      if _tmp
        while true

          _save5 = self.pos
          while true # sequence
            _save6 = self.pos
            _tmp = match_string("|")
            _tmp = _tmp ? nil : true
            self.pos = _save6
            unless _tmp
              self.pos = _save5
              break
            end
            _save7 = self.pos
            _tmp = _Newline()
            _tmp = _tmp ? nil : true
            self.pos = _save7
            unless _tmp
              self.pos = _save5
              break
            end
            _tmp = get_byte
            unless _tmp
              self.pos = _save5
            end
            break
          end # end sequence

          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text.strip ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_TableItem unless _tmp
    return _tmp
  end

  # TableLine = TableColumn+:line "|" @Newline { line }
  def _TableLine

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _ary = []
      _tmp = apply(:_TableColumn)
      if _tmp
        _ary << @result
        while true
          _tmp = apply(:_TableColumn)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save1
      end
      line = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string("|")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  line ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_TableLine unless _tmp
    return _tmp
  end

  # TableColumn = "|" < ("-"+ ":"? | ":" "-"*) > { text.start_with?(":") ? :left :                 text.end_with?(":") ? :right : nil               }
  def _TableColumn

    _save = self.pos
    while true # sequence
      _tmp = match_string("|")
      unless _tmp
        self.pos = _save
        break
      end
      _text_start = self.pos

      _save1 = self.pos
      while true # choice

        _save2 = self.pos
        while true # sequence
          _save3 = self.pos
          _tmp = match_string("-")
          if _tmp
            while true
              _tmp = match_string("-")
              break unless _tmp
            end
            _tmp = true
          else
            self.pos = _save3
          end
          unless _tmp
            self.pos = _save2
            break
          end
          _save4 = self.pos
          _tmp = match_string(":")
          unless _tmp
            _tmp = true
            self.pos = _save4
          end
          unless _tmp
            self.pos = _save2
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1

        _save5 = self.pos
        while true # sequence
          _tmp = match_string(":")
          unless _tmp
            self.pos = _save5
            break
          end
          while true
            _tmp = match_string("-")
            break unless _tmp
          end
          _tmp = true
          unless _tmp
            self.pos = _save5
          end
          break
        end # end sequence

        break if _tmp
        self.pos = _save1
        break
      end # end choice

      if _tmp
        text = get_text(_text_start)
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  text.start_with?(":") ? :left :
                text.end_with?(":") ? :right : nil
              ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_TableColumn unless _tmp
    return _tmp
  end

  # DefinitionList = &{ definition_lists? } DefinitionListItem+:list { RDoc::Markup::List.new :NOTE, *list.flatten }
  def _DefinitionList

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _tmp = begin;  definition_lists? ; end
      self.pos = _save1
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _ary = []
      _tmp = apply(:_DefinitionListItem)
      if _tmp
        _ary << @result
        while true
          _tmp = apply(:_DefinitionListItem)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save2
      end
      list = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  RDoc::Markup::List.new :NOTE, *list.flatten ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_DefinitionList unless _tmp
    return _tmp
  end

  # DefinitionListItem = DefinitionListLabel+:label DefinitionListDefinition+:defns { list_items = []                        list_items <<                          RDoc::Markup::ListItem.new(label, defns.shift)                         list_items.concat defns.map { |defn|                          RDoc::Markup::ListItem.new nil, defn                        } unless list_items.empty?                         list_items                      }
  def _DefinitionListItem

    _save = self.pos
    while true # sequence
      _save1 = self.pos
      _ary = []
      _tmp = apply(:_DefinitionListLabel)
      if _tmp
        _ary << @result
        while true
          _tmp = apply(:_DefinitionListLabel)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save1
      end
      label = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save2 = self.pos
      _ary = []
      _tmp = apply(:_DefinitionListDefinition)
      if _tmp
        _ary << @result
        while true
          _tmp = apply(:_DefinitionListDefinition)
          _ary << @result if _tmp
          break unless _tmp
        end
        _tmp = true
        @result = _ary
      else
        self.pos = _save2
      end
      defns = @result
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  list_items = []
                       list_items <<
                         RDoc::Markup::ListItem.new(label, defns.shift)

                       list_items.concat defns.map { |defn|
                         RDoc::Markup::ListItem.new nil, defn
                       } unless list_items.empty?

                       list_items
                     ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_DefinitionListItem unless _tmp
    return _tmp
  end

  # DefinitionListLabel = StrChunk:label @Sp @Newline { label }
  def _DefinitionListLabel

    _save = self.pos
    while true # sequence
      _tmp = apply(:_StrChunk)
      label = @result
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Sp()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Newline()
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  label ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_DefinitionListLabel unless _tmp
    return _tmp
  end

  # DefinitionListDefinition = @NonindentSpace ":" @Space Inlines:a @BlankLine+ { paragraph a }
  def _DefinitionListDefinition

    _save = self.pos
    while true # sequence
      _tmp = _NonindentSpace()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = match_string(":")
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = _Space()
      unless _tmp
        self.pos = _save
        break
      end
      _tmp = apply(:_Inlines)
      a = @result
      unless _tmp
        self.pos = _save
        break
      end
      _save1 = self.pos
      _tmp = _BlankLine()
      if _tmp
        while true
          _tmp = _BlankLine()
          break unless _tmp
        end
        _tmp = true
      else
        self.pos = _save1
      end
      unless _tmp
        self.pos = _save
        break
      end
      @result = begin;  paragraph a ; end
      _tmp = true
      unless _tmp
        self.pos = _save
      end
      break
    end # end sequence

    set_failed_rule :_DefinitionListDefinition unless _tmp
    return _tmp
  end

  Rules = {}
  Rules[:_root] = rule_info("root", "Doc")
  Rules[:_Doc] = rule_info("Doc", "BOM? Block*:a { RDoc::Markup::Document.new(*a.compact) }")
  Rules[:_Block] = rule_info("Block", "@BlankLine* (BlockQuote | Verbatim | CodeFence | Table | Note | Reference | HorizontalRule | Heading | OrderedList | BulletList | DefinitionList | HtmlBlock | StyleBlock | Para | Plain)")
  Rules[:_Para] = rule_info("Para", "@NonindentSpace Inlines:a @BlankLine+ { paragraph a }")
  Rules[:_Plain] = rule_info("Plain", "Inlines:a { paragraph a }")
  Rules[:_AtxInline] = rule_info("AtxInline", "!@Newline !(@Sp /\#*/ @Sp @Newline) Inline")
  Rules[:_AtxStart] = rule_info("AtxStart", "< /\\\#{1,6}/ > { text.length }")
  Rules[:_AtxHeading] = rule_info("AtxHeading", "AtxStart:s @Sp AtxInline+:a (@Sp /\#*/ @Sp)? @Newline { RDoc::Markup::Heading.new(s, a.join) }")
  Rules[:_SetextHeading] = rule_info("SetextHeading", "(SetextHeading1 | SetextHeading2)")
  Rules[:_SetextBottom1] = rule_info("SetextBottom1", "/={1,}/ @Newline")
  Rules[:_SetextBottom2] = rule_info("SetextBottom2", "/-{1,}/ @Newline")
  Rules[:_SetextHeading1] = rule_info("SetextHeading1", "&(@RawLine SetextBottom1) @StartList:a (!@Endline Inline:b { a << b })+ @Sp @Newline SetextBottom1 { RDoc::Markup::Heading.new(1, a.join) }")
  Rules[:_SetextHeading2] = rule_info("SetextHeading2", "&(@RawLine SetextBottom2) @StartList:a (!@Endline Inline:b { a << b })+ @Sp @Newline SetextBottom2 { RDoc::Markup::Heading.new(2, a.join) }")
  Rules[:_Heading] = rule_info("Heading", "(SetextHeading | AtxHeading)")
  Rules[:_BlockQuote] = rule_info("BlockQuote", "BlockQuoteRaw:a { RDoc::Markup::BlockQuote.new(*a) }")
  Rules[:_BlockQuoteRaw] = rule_info("BlockQuoteRaw", "@StartList:a (\">\" \" \"? Line:l { a << l } (!\">\" !@BlankLine Line:c { a << c })* (@BlankLine:n { a << n })*)+ { inner_parse a.join }")
  Rules[:_NonblankIndentedLine] = rule_info("NonblankIndentedLine", "!@BlankLine IndentedLine")
  Rules[:_VerbatimChunk] = rule_info("VerbatimChunk", "@BlankLine*:a NonblankIndentedLine+:b { a.concat b }")
  Rules[:_Verbatim] = rule_info("Verbatim", "VerbatimChunk+:a { RDoc::Markup::Verbatim.new(*a.flatten) }")
  Rules[:_HorizontalRule] = rule_info("HorizontalRule", "@NonindentSpace (\"*\" @Sp \"*\" @Sp \"*\" (@Sp \"*\")* | \"-\" @Sp \"-\" @Sp \"-\" (@Sp \"-\")* | \"_\" @Sp \"_\" @Sp \"_\" (@Sp \"_\")*) @Sp @Newline @BlankLine+ { RDoc::Markup::Rule.new 1 }")
  Rules[:_Bullet] = rule_info("Bullet", "!HorizontalRule @NonindentSpace /[+*-]/ @Spacechar+")
  Rules[:_BulletList] = rule_info("BulletList", "&Bullet (ListTight | ListLoose):a { RDoc::Markup::List.new(:BULLET, *a) }")
  Rules[:_ListTight] = rule_info("ListTight", "ListItemTight+:a @BlankLine* !(Bullet | Enumerator) { a }")
  Rules[:_ListLoose] = rule_info("ListLoose", "@StartList:a (ListItem:b @BlankLine* { a << b })+ { a }")
  Rules[:_ListItem] = rule_info("ListItem", "(Bullet | Enumerator) @StartList:a ListBlock:b { a << b } (ListContinuationBlock:c { a.push(*c) })* { list_item_from a }")
  Rules[:_ListItemTight] = rule_info("ListItemTight", "(Bullet | Enumerator) ListBlock:a (!@BlankLine ListContinuationBlock:b { a.push(*b) })* !ListContinuationBlock { list_item_from a }")
  Rules[:_ListBlock] = rule_info("ListBlock", "!@BlankLine Line:a ListBlockLine*:c { [a, *c] }")
  Rules[:_ListContinuationBlock] = rule_info("ListContinuationBlock", "@StartList:a @BlankLine* { a << \"\\n\" } (Indent ListBlock:b { a.concat b })+ { a }")
  Rules[:_Enumerator] = rule_info("Enumerator", "@NonindentSpace [0-9]+ \".\" @Spacechar+")
  Rules[:_OrderedList] = rule_info("OrderedList", "&Enumerator (ListTight | ListLoose):a { RDoc::Markup::List.new(:NUMBER, *a) }")
  Rules[:_ListBlockLine] = rule_info("ListBlockLine", "!@BlankLine !(Indent? (Bullet | Enumerator)) !HorizontalRule OptionallyIndentedLine")
  Rules[:_HtmlOpenAnchor] = rule_info("HtmlOpenAnchor", "\"<\" Spnl (\"a\" | \"A\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlCloseAnchor] = rule_info("HtmlCloseAnchor", "\"<\" Spnl \"/\" (\"a\" | \"A\") Spnl \">\"")
  Rules[:_HtmlAnchor] = rule_info("HtmlAnchor", "HtmlOpenAnchor (HtmlAnchor | !HtmlCloseAnchor .)* HtmlCloseAnchor")
  Rules[:_HtmlBlockOpenAddress] = rule_info("HtmlBlockOpenAddress", "\"<\" Spnl (\"address\" | \"ADDRESS\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseAddress] = rule_info("HtmlBlockCloseAddress", "\"<\" Spnl \"/\" (\"address\" | \"ADDRESS\") Spnl \">\"")
  Rules[:_HtmlBlockAddress] = rule_info("HtmlBlockAddress", "HtmlBlockOpenAddress (HtmlBlockAddress | !HtmlBlockCloseAddress .)* HtmlBlockCloseAddress")
  Rules[:_HtmlBlockOpenBlockquote] = rule_info("HtmlBlockOpenBlockquote", "\"<\" Spnl (\"blockquote\" | \"BLOCKQUOTE\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseBlockquote] = rule_info("HtmlBlockCloseBlockquote", "\"<\" Spnl \"/\" (\"blockquote\" | \"BLOCKQUOTE\") Spnl \">\"")
  Rules[:_HtmlBlockBlockquote] = rule_info("HtmlBlockBlockquote", "HtmlBlockOpenBlockquote (HtmlBlockBlockquote | !HtmlBlockCloseBlockquote .)* HtmlBlockCloseBlockquote")
  Rules[:_HtmlBlockOpenCenter] = rule_info("HtmlBlockOpenCenter", "\"<\" Spnl (\"center\" | \"CENTER\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseCenter] = rule_info("HtmlBlockCloseCenter", "\"<\" Spnl \"/\" (\"center\" | \"CENTER\") Spnl \">\"")
  Rules[:_HtmlBlockCenter] = rule_info("HtmlBlockCenter", "HtmlBlockOpenCenter (HtmlBlockCenter | !HtmlBlockCloseCenter .)* HtmlBlockCloseCenter")
  Rules[:_HtmlBlockOpenDir] = rule_info("HtmlBlockOpenDir", "\"<\" Spnl (\"dir\" | \"DIR\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseDir] = rule_info("HtmlBlockCloseDir", "\"<\" Spnl \"/\" (\"dir\" | \"DIR\") Spnl \">\"")
  Rules[:_HtmlBlockDir] = rule_info("HtmlBlockDir", "HtmlBlockOpenDir (HtmlBlockDir | !HtmlBlockCloseDir .)* HtmlBlockCloseDir")
  Rules[:_HtmlBlockOpenDiv] = rule_info("HtmlBlockOpenDiv", "\"<\" Spnl (\"div\" | \"DIV\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseDiv] = rule_info("HtmlBlockCloseDiv", "\"<\" Spnl \"/\" (\"div\" | \"DIV\") Spnl \">\"")
  Rules[:_HtmlBlockDiv] = rule_info("HtmlBlockDiv", "HtmlBlockOpenDiv (HtmlBlockDiv | !HtmlBlockCloseDiv .)* HtmlBlockCloseDiv")
  Rules[:_HtmlBlockOpenDl] = rule_info("HtmlBlockOpenDl", "\"<\" Spnl (\"dl\" | \"DL\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseDl] = rule_info("HtmlBlockCloseDl", "\"<\" Spnl \"/\" (\"dl\" | \"DL\") Spnl \">\"")
  Rules[:_HtmlBlockDl] = rule_info("HtmlBlockDl", "HtmlBlockOpenDl (HtmlBlockDl | !HtmlBlockCloseDl .)* HtmlBlockCloseDl")
  Rules[:_HtmlBlockOpenFieldset] = rule_info("HtmlBlockOpenFieldset", "\"<\" Spnl (\"fieldset\" | \"FIELDSET\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseFieldset] = rule_info("HtmlBlockCloseFieldset", "\"<\" Spnl \"/\" (\"fieldset\" | \"FIELDSET\") Spnl \">\"")
  Rules[:_HtmlBlockFieldset] = rule_info("HtmlBlockFieldset", "HtmlBlockOpenFieldset (HtmlBlockFieldset | !HtmlBlockCloseFieldset .)* HtmlBlockCloseFieldset")
  Rules[:_HtmlBlockOpenForm] = rule_info("HtmlBlockOpenForm", "\"<\" Spnl (\"form\" | \"FORM\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseForm] = rule_info("HtmlBlockCloseForm", "\"<\" Spnl \"/\" (\"form\" | \"FORM\") Spnl \">\"")
  Rules[:_HtmlBlockForm] = rule_info("HtmlBlockForm", "HtmlBlockOpenForm (HtmlBlockForm | !HtmlBlockCloseForm .)* HtmlBlockCloseForm")
  Rules[:_HtmlBlockOpenH1] = rule_info("HtmlBlockOpenH1", "\"<\" Spnl (\"h1\" | \"H1\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseH1] = rule_info("HtmlBlockCloseH1", "\"<\" Spnl \"/\" (\"h1\" | \"H1\") Spnl \">\"")
  Rules[:_HtmlBlockH1] = rule_info("HtmlBlockH1", "HtmlBlockOpenH1 (HtmlBlockH1 | !HtmlBlockCloseH1 .)* HtmlBlockCloseH1")
  Rules[:_HtmlBlockOpenH2] = rule_info("HtmlBlockOpenH2", "\"<\" Spnl (\"h2\" | \"H2\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseH2] = rule_info("HtmlBlockCloseH2", "\"<\" Spnl \"/\" (\"h2\" | \"H2\") Spnl \">\"")
  Rules[:_HtmlBlockH2] = rule_info("HtmlBlockH2", "HtmlBlockOpenH2 (HtmlBlockH2 | !HtmlBlockCloseH2 .)* HtmlBlockCloseH2")
  Rules[:_HtmlBlockOpenH3] = rule_info("HtmlBlockOpenH3", "\"<\" Spnl (\"h3\" | \"H3\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseH3] = rule_info("HtmlBlockCloseH3", "\"<\" Spnl \"/\" (\"h3\" | \"H3\") Spnl \">\"")
  Rules[:_HtmlBlockH3] = rule_info("HtmlBlockH3", "HtmlBlockOpenH3 (HtmlBlockH3 | !HtmlBlockCloseH3 .)* HtmlBlockCloseH3")
  Rules[:_HtmlBlockOpenH4] = rule_info("HtmlBlockOpenH4", "\"<\" Spnl (\"h4\" | \"H4\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseH4] = rule_info("HtmlBlockCloseH4", "\"<\" Spnl \"/\" (\"h4\" | \"H4\") Spnl \">\"")
  Rules[:_HtmlBlockH4] = rule_info("HtmlBlockH4", "HtmlBlockOpenH4 (HtmlBlockH4 | !HtmlBlockCloseH4 .)* HtmlBlockCloseH4")
  Rules[:_HtmlBlockOpenH5] = rule_info("HtmlBlockOpenH5", "\"<\" Spnl (\"h5\" | \"H5\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseH5] = rule_info("HtmlBlockCloseH5", "\"<\" Spnl \"/\" (\"h5\" | \"H5\") Spnl \">\"")
  Rules[:_HtmlBlockH5] = rule_info("HtmlBlockH5", "HtmlBlockOpenH5 (HtmlBlockH5 | !HtmlBlockCloseH5 .)* HtmlBlockCloseH5")
  Rules[:_HtmlBlockOpenH6] = rule_info("HtmlBlockOpenH6", "\"<\" Spnl (\"h6\" | \"H6\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseH6] = rule_info("HtmlBlockCloseH6", "\"<\" Spnl \"/\" (\"h6\" | \"H6\") Spnl \">\"")
  Rules[:_HtmlBlockH6] = rule_info("HtmlBlockH6", "HtmlBlockOpenH6 (HtmlBlockH6 | !HtmlBlockCloseH6 .)* HtmlBlockCloseH6")
  Rules[:_HtmlBlockOpenMenu] = rule_info("HtmlBlockOpenMenu", "\"<\" Spnl (\"menu\" | \"MENU\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseMenu] = rule_info("HtmlBlockCloseMenu", "\"<\" Spnl \"/\" (\"menu\" | \"MENU\") Spnl \">\"")
  Rules[:_HtmlBlockMenu] = rule_info("HtmlBlockMenu", "HtmlBlockOpenMenu (HtmlBlockMenu | !HtmlBlockCloseMenu .)* HtmlBlockCloseMenu")
  Rules[:_HtmlBlockOpenNoframes] = rule_info("HtmlBlockOpenNoframes", "\"<\" Spnl (\"noframes\" | \"NOFRAMES\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseNoframes] = rule_info("HtmlBlockCloseNoframes", "\"<\" Spnl \"/\" (\"noframes\" | \"NOFRAMES\") Spnl \">\"")
  Rules[:_HtmlBlockNoframes] = rule_info("HtmlBlockNoframes", "HtmlBlockOpenNoframes (HtmlBlockNoframes | !HtmlBlockCloseNoframes .)* HtmlBlockCloseNoframes")
  Rules[:_HtmlBlockOpenNoscript] = rule_info("HtmlBlockOpenNoscript", "\"<\" Spnl (\"noscript\" | \"NOSCRIPT\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseNoscript] = rule_info("HtmlBlockCloseNoscript", "\"<\" Spnl \"/\" (\"noscript\" | \"NOSCRIPT\") Spnl \">\"")
  Rules[:_HtmlBlockNoscript] = rule_info("HtmlBlockNoscript", "HtmlBlockOpenNoscript (HtmlBlockNoscript | !HtmlBlockCloseNoscript .)* HtmlBlockCloseNoscript")
  Rules[:_HtmlBlockOpenOl] = rule_info("HtmlBlockOpenOl", "\"<\" Spnl (\"ol\" | \"OL\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseOl] = rule_info("HtmlBlockCloseOl", "\"<\" Spnl \"/\" (\"ol\" | \"OL\") Spnl \">\"")
  Rules[:_HtmlBlockOl] = rule_info("HtmlBlockOl", "HtmlBlockOpenOl (HtmlBlockOl | !HtmlBlockCloseOl .)* HtmlBlockCloseOl")
  Rules[:_HtmlBlockOpenP] = rule_info("HtmlBlockOpenP", "\"<\" Spnl (\"p\" | \"P\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseP] = rule_info("HtmlBlockCloseP", "\"<\" Spnl \"/\" (\"p\" | \"P\") Spnl \">\"")
  Rules[:_HtmlBlockP] = rule_info("HtmlBlockP", "HtmlBlockOpenP (HtmlBlockP | !HtmlBlockCloseP .)* HtmlBlockCloseP")
  Rules[:_HtmlBlockOpenPre] = rule_info("HtmlBlockOpenPre", "\"<\" Spnl (\"pre\" | \"PRE\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockClosePre] = rule_info("HtmlBlockClosePre", "\"<\" Spnl \"/\" (\"pre\" | \"PRE\") Spnl \">\"")
  Rules[:_HtmlBlockPre] = rule_info("HtmlBlockPre", "HtmlBlockOpenPre (HtmlBlockPre | !HtmlBlockClosePre .)* HtmlBlockClosePre")
  Rules[:_HtmlBlockOpenTable] = rule_info("HtmlBlockOpenTable", "\"<\" Spnl (\"table\" | \"TABLE\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseTable] = rule_info("HtmlBlockCloseTable", "\"<\" Spnl \"/\" (\"table\" | \"TABLE\") Spnl \">\"")
  Rules[:_HtmlBlockTable] = rule_info("HtmlBlockTable", "HtmlBlockOpenTable (HtmlBlockTable | !HtmlBlockCloseTable .)* HtmlBlockCloseTable")
  Rules[:_HtmlBlockOpenUl] = rule_info("HtmlBlockOpenUl", "\"<\" Spnl (\"ul\" | \"UL\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseUl] = rule_info("HtmlBlockCloseUl", "\"<\" Spnl \"/\" (\"ul\" | \"UL\") Spnl \">\"")
  Rules[:_HtmlBlockUl] = rule_info("HtmlBlockUl", "HtmlBlockOpenUl (HtmlBlockUl | !HtmlBlockCloseUl .)* HtmlBlockCloseUl")
  Rules[:_HtmlBlockOpenDd] = rule_info("HtmlBlockOpenDd", "\"<\" Spnl (\"dd\" | \"DD\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseDd] = rule_info("HtmlBlockCloseDd", "\"<\" Spnl \"/\" (\"dd\" | \"DD\") Spnl \">\"")
  Rules[:_HtmlBlockDd] = rule_info("HtmlBlockDd", "HtmlBlockOpenDd (HtmlBlockDd | !HtmlBlockCloseDd .)* HtmlBlockCloseDd")
  Rules[:_HtmlBlockOpenDt] = rule_info("HtmlBlockOpenDt", "\"<\" Spnl (\"dt\" | \"DT\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseDt] = rule_info("HtmlBlockCloseDt", "\"<\" Spnl \"/\" (\"dt\" | \"DT\") Spnl \">\"")
  Rules[:_HtmlBlockDt] = rule_info("HtmlBlockDt", "HtmlBlockOpenDt (HtmlBlockDt | !HtmlBlockCloseDt .)* HtmlBlockCloseDt")
  Rules[:_HtmlBlockOpenFrameset] = rule_info("HtmlBlockOpenFrameset", "\"<\" Spnl (\"frameset\" | \"FRAMESET\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseFrameset] = rule_info("HtmlBlockCloseFrameset", "\"<\" Spnl \"/\" (\"frameset\" | \"FRAMESET\") Spnl \">\"")
  Rules[:_HtmlBlockFrameset] = rule_info("HtmlBlockFrameset", "HtmlBlockOpenFrameset (HtmlBlockFrameset | !HtmlBlockCloseFrameset .)* HtmlBlockCloseFrameset")
  Rules[:_HtmlBlockOpenLi] = rule_info("HtmlBlockOpenLi", "\"<\" Spnl (\"li\" | \"LI\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseLi] = rule_info("HtmlBlockCloseLi", "\"<\" Spnl \"/\" (\"li\" | \"LI\") Spnl \">\"")
  Rules[:_HtmlBlockLi] = rule_info("HtmlBlockLi", "HtmlBlockOpenLi (HtmlBlockLi | !HtmlBlockCloseLi .)* HtmlBlockCloseLi")
  Rules[:_HtmlBlockOpenTbody] = rule_info("HtmlBlockOpenTbody", "\"<\" Spnl (\"tbody\" | \"TBODY\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseTbody] = rule_info("HtmlBlockCloseTbody", "\"<\" Spnl \"/\" (\"tbody\" | \"TBODY\") Spnl \">\"")
  Rules[:_HtmlBlockTbody] = rule_info("HtmlBlockTbody", "HtmlBlockOpenTbody (HtmlBlockTbody | !HtmlBlockCloseTbody .)* HtmlBlockCloseTbody")
  Rules[:_HtmlBlockOpenTd] = rule_info("HtmlBlockOpenTd", "\"<\" Spnl (\"td\" | \"TD\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseTd] = rule_info("HtmlBlockCloseTd", "\"<\" Spnl \"/\" (\"td\" | \"TD\") Spnl \">\"")
  Rules[:_HtmlBlockTd] = rule_info("HtmlBlockTd", "HtmlBlockOpenTd (HtmlBlockTd | !HtmlBlockCloseTd .)* HtmlBlockCloseTd")
  Rules[:_HtmlBlockOpenTfoot] = rule_info("HtmlBlockOpenTfoot", "\"<\" Spnl (\"tfoot\" | \"TFOOT\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseTfoot] = rule_info("HtmlBlockCloseTfoot", "\"<\" Spnl \"/\" (\"tfoot\" | \"TFOOT\") Spnl \">\"")
  Rules[:_HtmlBlockTfoot] = rule_info("HtmlBlockTfoot", "HtmlBlockOpenTfoot (HtmlBlockTfoot | !HtmlBlockCloseTfoot .)* HtmlBlockCloseTfoot")
  Rules[:_HtmlBlockOpenTh] = rule_info("HtmlBlockOpenTh", "\"<\" Spnl (\"th\" | \"TH\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseTh] = rule_info("HtmlBlockCloseTh", "\"<\" Spnl \"/\" (\"th\" | \"TH\") Spnl \">\"")
  Rules[:_HtmlBlockTh] = rule_info("HtmlBlockTh", "HtmlBlockOpenTh (HtmlBlockTh | !HtmlBlockCloseTh .)* HtmlBlockCloseTh")
  Rules[:_HtmlBlockOpenThead] = rule_info("HtmlBlockOpenThead", "\"<\" Spnl (\"thead\" | \"THEAD\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseThead] = rule_info("HtmlBlockCloseThead", "\"<\" Spnl \"/\" (\"thead\" | \"THEAD\") Spnl \">\"")
  Rules[:_HtmlBlockThead] = rule_info("HtmlBlockThead", "HtmlBlockOpenThead (HtmlBlockThead | !HtmlBlockCloseThead .)* HtmlBlockCloseThead")
  Rules[:_HtmlBlockOpenTr] = rule_info("HtmlBlockOpenTr", "\"<\" Spnl (\"tr\" | \"TR\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseTr] = rule_info("HtmlBlockCloseTr", "\"<\" Spnl \"/\" (\"tr\" | \"TR\") Spnl \">\"")
  Rules[:_HtmlBlockTr] = rule_info("HtmlBlockTr", "HtmlBlockOpenTr (HtmlBlockTr | !HtmlBlockCloseTr .)* HtmlBlockCloseTr")
  Rules[:_HtmlBlockOpenScript] = rule_info("HtmlBlockOpenScript", "\"<\" Spnl (\"script\" | \"SCRIPT\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseScript] = rule_info("HtmlBlockCloseScript", "\"<\" Spnl \"/\" (\"script\" | \"SCRIPT\") Spnl \">\"")
  Rules[:_HtmlBlockScript] = rule_info("HtmlBlockScript", "HtmlBlockOpenScript (!HtmlBlockCloseScript .)* HtmlBlockCloseScript")
  Rules[:_HtmlBlockOpenHead] = rule_info("HtmlBlockOpenHead", "\"<\" Spnl (\"head\" | \"HEAD\") Spnl HtmlAttribute* \">\"")
  Rules[:_HtmlBlockCloseHead] = rule_info("HtmlBlockCloseHead", "\"<\" Spnl \"/\" (\"head\" | \"HEAD\") Spnl \">\"")
  Rules[:_HtmlBlockHead] = rule_info("HtmlBlockHead", "HtmlBlockOpenHead (!HtmlBlockCloseHead .)* HtmlBlockCloseHead")
  Rules[:_HtmlBlockInTags] = rule_info("HtmlBlockInTags", "(HtmlAnchor | HtmlBlockAddress | HtmlBlockBlockquote | HtmlBlockCenter | HtmlBlockDir | HtmlBlockDiv | HtmlBlockDl | HtmlBlockFieldset | HtmlBlockForm | HtmlBlockH1 | HtmlBlockH2 | HtmlBlockH3 | HtmlBlockH4 | HtmlBlockH5 | HtmlBlockH6 | HtmlBlockMenu | HtmlBlockNoframes | HtmlBlockNoscript | HtmlBlockOl | HtmlBlockP | HtmlBlockPre | HtmlBlockTable | HtmlBlockUl | HtmlBlockDd | HtmlBlockDt | HtmlBlockFrameset | HtmlBlockLi | HtmlBlockTbody | HtmlBlockTd | HtmlBlockTfoot | HtmlBlockTh | HtmlBlockThead | HtmlBlockTr | HtmlBlockScript | HtmlBlockHead)")
  Rules[:_HtmlBlock] = rule_info("HtmlBlock", "< (HtmlBlockInTags | HtmlComment | HtmlBlockSelfClosing | HtmlUnclosed) > @BlankLine+ { if html? then                 RDoc::Markup::Raw.new text               end }")
  Rules[:_HtmlUnclosed] = rule_info("HtmlUnclosed", "\"<\" Spnl HtmlUnclosedType Spnl HtmlAttribute* Spnl \">\"")
  Rules[:_HtmlUnclosedType] = rule_info("HtmlUnclosedType", "(\"HR\" | \"hr\")")
  Rules[:_HtmlBlockSelfClosing] = rule_info("HtmlBlockSelfClosing", "\"<\" Spnl HtmlBlockType Spnl HtmlAttribute* \"/\" Spnl \">\"")
  Rules[:_HtmlBlockType] = rule_info("HtmlBlockType", "(\"ADDRESS\" | \"BLOCKQUOTE\" | \"CENTER\" | \"DD\" | \"DIR\" | \"DIV\" | \"DL\" | \"DT\" | \"FIELDSET\" | \"FORM\" | \"FRAMESET\" | \"H1\" | \"H2\" | \"H3\" | \"H4\" | \"H5\" | \"H6\" | \"HR\" | \"ISINDEX\" | \"LI\" | \"MENU\" | \"NOFRAMES\" | \"NOSCRIPT\" | \"OL\" | \"P\" | \"PRE\" | \"SCRIPT\" | \"TABLE\" | \"TBODY\" | \"TD\" | \"TFOOT\" | \"TH\" | \"THEAD\" | \"TR\" | \"UL\" | \"address\" | \"blockquote\" | \"center\" | \"dd\" | \"dir\" | \"div\" | \"dl\" | \"dt\" | \"fieldset\" | \"form\" | \"frameset\" | \"h1\" | \"h2\" | \"h3\" | \"h4\" | \"h5\" | \"h6\" | \"hr\" | \"isindex\" | \"li\" | \"menu\" | \"noframes\" | \"noscript\" | \"ol\" | \"p\" | \"pre\" | \"script\" | \"table\" | \"tbody\" | \"td\" | \"tfoot\" | \"th\" | \"thead\" | \"tr\" | \"ul\")")
  Rules[:_StyleOpen] = rule_info("StyleOpen", "\"<\" Spnl (\"style\" | \"STYLE\") Spnl HtmlAttribute* \">\"")
  Rules[:_StyleClose] = rule_info("StyleClose", "\"<\" Spnl \"/\" (\"style\" | \"STYLE\") Spnl \">\"")
  Rules[:_InStyleTags] = rule_info("InStyleTags", "StyleOpen (!StyleClose .)* StyleClose")
  Rules[:_StyleBlock] = rule_info("StyleBlock", "< InStyleTags > @BlankLine* { if css? then                     RDoc::Markup::Raw.new text                   end }")
  Rules[:_Inlines] = rule_info("Inlines", "(!@Endline Inline:i { i } | @Endline:c !(&{ github? } Ticks3 /[^`\\n]*$/) &Inline { c })+:chunks @Endline? { chunks }")
  Rules[:_Inline] = rule_info("Inline", "(Str | @Endline | UlOrStarLine | @Space | Strong | Emph | Strike | Image | Link | NoteReference | InlineNote | Code | RawHtml | Entity | EscapedChar | Symbol)")
  Rules[:_Space] = rule_info("Space", "@Spacechar+ { \" \" }")
  Rules[:_Str] = rule_info("Str", "@StartList:a < @NormalChar+ > { a = text } (StrChunk:c { a << c })* { a }")
  Rules[:_StrChunk] = rule_info("StrChunk", "< (@NormalChar | /_+/ &Alphanumeric)+ > { text }")
  Rules[:_EscapedChar] = rule_info("EscapedChar", "\"\\\\\" !@Newline < /[:\\\\`|*_{}\\[\\]()\#+.!><-]/ > { text }")
  Rules[:_Entity] = rule_info("Entity", "(HexEntity | DecEntity | CharEntity):a { a }")
  Rules[:_Endline] = rule_info("Endline", "(@LineBreak | @TerminalEndline | @NormalEndline)")
  Rules[:_NormalEndline] = rule_info("NormalEndline", "@Sp @Newline !@BlankLine !\">\" !AtxStart !(Line /={1,}|-{1,}/ @Newline) { \"\\n\" }")
  Rules[:_TerminalEndline] = rule_info("TerminalEndline", "@Sp @Newline @Eof")
  Rules[:_LineBreak] = rule_info("LineBreak", "\"  \" @NormalEndline { RDoc::Markup::HardBreak.new }")
  Rules[:_Symbol] = rule_info("Symbol", "< @SpecialChar > { text }")
  Rules[:_UlOrStarLine] = rule_info("UlOrStarLine", "(UlLine | StarLine):a { a }")
  Rules[:_StarLine] = rule_info("StarLine", "(< /\\*{4,}/ > { text } | < @Spacechar /\\*+/ &@Spacechar > { text })")
  Rules[:_UlLine] = rule_info("UlLine", "(< /_{4,}/ > { text } | < @Spacechar /_+/ &@Spacechar > { text })")
  Rules[:_Emph] = rule_info("Emph", "(EmphStar | EmphUl)")
  Rules[:_Whitespace] = rule_info("Whitespace", "(@Spacechar | @Newline)")
  Rules[:_EmphStar] = rule_info("EmphStar", "\"*\" !@Whitespace @StartList:a (!\"*\" Inline:b { a << b } | StrongStar:b { a << b })+ \"*\" { emphasis a.join }")
  Rules[:_EmphUl] = rule_info("EmphUl", "\"_\" !@Whitespace @StartList:a (!\"_\" Inline:b { a << b } | StrongUl:b { a << b })+ \"_\" { emphasis a.join }")
  Rules[:_Strong] = rule_info("Strong", "(StrongStar | StrongUl)")
  Rules[:_StrongStar] = rule_info("StrongStar", "\"**\" !@Whitespace @StartList:a (!\"**\" Inline:b { a << b })+ \"**\" { strong a.join }")
  Rules[:_StrongUl] = rule_info("StrongUl", "\"__\" !@Whitespace @StartList:a (!\"__\" Inline:b { a << b })+ \"__\" { strong a.join }")
  Rules[:_Strike] = rule_info("Strike", "&{ strike? } \"~~\" !@Whitespace @StartList:a (!\"~~\" Inline:b { a << b })+ \"~~\" { strike a.join }")
  Rules[:_Image] = rule_info("Image", "\"!\" (ExplicitLink | ReferenceLink):a { \"rdoc-image:\#{a[/\\[(.*)\\]/, 1]}\" }")
  Rules[:_Link] = rule_info("Link", "(ExplicitLink | ReferenceLink | AutoLink)")
  Rules[:_ReferenceLink] = rule_info("ReferenceLink", "(ReferenceLinkDouble | ReferenceLinkSingle)")
  Rules[:_ReferenceLinkDouble] = rule_info("ReferenceLinkDouble", "Label:content < Spnl > !\"[]\" Label:label { link_to content, label, text }")
  Rules[:_ReferenceLinkSingle] = rule_info("ReferenceLinkSingle", "Label:content < (Spnl \"[]\")? > { link_to content, content, text }")
  Rules[:_ExplicitLink] = rule_info("ExplicitLink", "Label:l \"(\" @Sp Source:s Spnl Title @Sp \")\" { \"{\#{l}}[\#{s}]\" }")
  Rules[:_Source] = rule_info("Source", "(\"<\" < SourceContents > \">\" | < SourceContents >) { text }")
  Rules[:_SourceContents] = rule_info("SourceContents", "((!\"(\" !\")\" !\">\" Nonspacechar)+ | \"(\" SourceContents \")\")*")
  Rules[:_Title] = rule_info("Title", "(TitleSingle | TitleDouble | \"\"):a { a }")
  Rules[:_TitleSingle] = rule_info("TitleSingle", "\"'\" (!(\"'\" @Sp (\")\" | @Newline)) .)* \"'\"")
  Rules[:_TitleDouble] = rule_info("TitleDouble", "\"\\\"\" (!(\"\\\"\" @Sp (\")\" | @Newline)) .)* \"\\\"\"")
  Rules[:_AutoLink] = rule_info("AutoLink", "(AutoLinkUrl | AutoLinkEmail)")
  Rules[:_AutoLinkUrl] = rule_info("AutoLinkUrl", "\"<\" < /[A-Za-z]+/ \"://\" (!@Newline !\">\" .)+ > \">\" { text }")
  Rules[:_AutoLinkEmail] = rule_info("AutoLinkEmail", "\"<\" \"mailto:\"? < /[\\w+.\\/!%~$-]+/i \"@\" (!@Newline !\">\" .)+ > \">\" { \"mailto:\#{text}\" }")
  Rules[:_Reference] = rule_info("Reference", "@NonindentSpace !\"[]\" Label:label \":\" Spnl RefSrc:link RefTitle @BlankLine+ { \# TODO use title               reference label, link               nil             }")
  Rules[:_Label] = rule_info("Label", "\"[\" (!\"^\" &{ notes? } | &. &{ !notes? }) @StartList:a (!\"]\" Inline:l { a << l })* \"]\" { a.join.gsub(/\\s+/, ' ') }")
  Rules[:_RefSrc] = rule_info("RefSrc", "< Nonspacechar+ > { text }")
  Rules[:_RefTitle] = rule_info("RefTitle", "(RefTitleSingle | RefTitleDouble | RefTitleParens | EmptyTitle)")
  Rules[:_EmptyTitle] = rule_info("EmptyTitle", "\"\"")
  Rules[:_RefTitleSingle] = rule_info("RefTitleSingle", "Spnl \"'\" < (!(\"'\" @Sp @Newline | @Newline) .)* > \"'\" { text }")
  Rules[:_RefTitleDouble] = rule_info("RefTitleDouble", "Spnl \"\\\"\" < (!(\"\\\"\" @Sp @Newline | @Newline) .)* > \"\\\"\" { text }")
  Rules[:_RefTitleParens] = rule_info("RefTitleParens", "Spnl \"(\" < (!(\")\" @Sp @Newline | @Newline) .)* > \")\" { text }")
  Rules[:_References] = rule_info("References", "(Reference | SkipBlock)*")
  Rules[:_Ticks1] = rule_info("Ticks1", "\"`\" !\"`\"")
  Rules[:_Ticks2] = rule_info("Ticks2", "\"``\" !\"`\"")
  Rules[:_Ticks3] = rule_info("Ticks3", "\"```\" !\"`\"")
  Rules[:_Ticks4] = rule_info("Ticks4", "\"````\" !\"`\"")
  Rules[:_Ticks5] = rule_info("Ticks5", "\"`````\" !\"`\"")
  Rules[:_Code] = rule_info("Code", "(Ticks1 @Sp < ((!\"`\" Nonspacechar)+ | !Ticks1 /`+/ | !(@Sp Ticks1) (@Spacechar | @Newline !@BlankLine))+ > @Sp Ticks1 | Ticks2 @Sp < ((!\"`\" Nonspacechar)+ | !Ticks2 /`+/ | !(@Sp Ticks2) (@Spacechar | @Newline !@BlankLine))+ > @Sp Ticks2 | Ticks3 @Sp < ((!\"`\" Nonspacechar)+ | !Ticks3 /`+/ | !(@Sp Ticks3) (@Spacechar | @Newline !@BlankLine))+ > @Sp Ticks3 | Ticks4 @Sp < ((!\"`\" Nonspacechar)+ | !Ticks4 /`+/ | !(@Sp Ticks4) (@Spacechar | @Newline !@BlankLine))+ > @Sp Ticks4 | Ticks5 @Sp < ((!\"`\" Nonspacechar)+ | !Ticks5 /`+/ | !(@Sp Ticks5) (@Spacechar | @Newline !@BlankLine))+ > @Sp Ticks5) { \"<code>\#{text}</code>\" }")
  Rules[:_RawHtml] = rule_info("RawHtml", "< (HtmlComment | HtmlBlockScript | HtmlTag) > { if html? then text else '' end }")
  Rules[:_BlankLine] = rule_info("BlankLine", "@Sp @Newline { \"\\n\" }")
  Rules[:_Quoted] = rule_info("Quoted", "(\"\\\"\" (!\"\\\"\" .)* \"\\\"\" | \"'\" (!\"'\" .)* \"'\")")
  Rules[:_HtmlAttribute] = rule_info("HtmlAttribute", "(AlphanumericAscii | \"-\")+ Spnl (\"=\" Spnl (Quoted | (!\">\" Nonspacechar)+))? Spnl")
  Rules[:_HtmlComment] = rule_info("HtmlComment", "\"<!--\" (!\"-->\" .)* \"-->\"")
  Rules[:_HtmlTag] = rule_info("HtmlTag", "\"<\" Spnl \"/\"? AlphanumericAscii+ Spnl HtmlAttribute* \"/\"? Spnl \">\"")
  Rules[:_Eof] = rule_info("Eof", "!.")
  Rules[:_Nonspacechar] = rule_info("Nonspacechar", "!@Spacechar !@Newline .")
  Rules[:_Sp] = rule_info("Sp", "@Spacechar*")
  Rules[:_Spnl] = rule_info("Spnl", "@Sp (@Newline @Sp)?")
  Rules[:_SpecialChar] = rule_info("SpecialChar", "(/[~*_`&\\[\\]()<!\#\\\\'\"]/ | @ExtendedSpecialChar)")
  Rules[:_NormalChar] = rule_info("NormalChar", "!(@SpecialChar | @Spacechar | @Newline) .")
  Rules[:_Digit] = rule_info("Digit", "[0-9]")
  Rules[:_Alphanumeric] = rule_info("Alphanumeric", "%literals.Alphanumeric")
  Rules[:_AlphanumericAscii] = rule_info("AlphanumericAscii", "%literals.AlphanumericAscii")
  Rules[:_BOM] = rule_info("BOM", "%literals.BOM")
  Rules[:_Newline] = rule_info("Newline", "%literals.Newline")
  Rules[:_Spacechar] = rule_info("Spacechar", "%literals.Spacechar")
  Rules[:_HexEntity] = rule_info("HexEntity", "/&\#x/i < /[0-9a-fA-F]+/ > \";\" { [text.to_i(16)].pack 'U' }")
  Rules[:_DecEntity] = rule_info("DecEntity", "\"&\#\" < /[0-9]+/ > \";\" { [text.to_i].pack 'U' }")
  Rules[:_CharEntity] = rule_info("CharEntity", "\"&\" < /[A-Za-z0-9]+/ > \";\" { if entity = HTML_ENTITIES[text] then                  entity.pack 'U*'                else                  \"&\#{text};\"                end              }")
  Rules[:_NonindentSpace] = rule_info("NonindentSpace", "/ {0,3}/")
  Rules[:_Indent] = rule_info("Indent", "/\\t|    /")
  Rules[:_IndentedLine] = rule_info("IndentedLine", "Indent Line")
  Rules[:_OptionallyIndentedLine] = rule_info("OptionallyIndentedLine", "Indent? Line")
  Rules[:_StartList] = rule_info("StartList", "&. { [] }")
  Rules[:_Line] = rule_info("Line", "@RawLine:a { a }")
  Rules[:_RawLine] = rule_info("RawLine", "(< (!\"\\r\" !\"\\n\" .)* @Newline > | < .+ > @Eof) { text }")
  Rules[:_SkipBlock] = rule_info("SkipBlock", "(HtmlBlock | (!\"\#\" !SetextBottom1 !SetextBottom2 !@BlankLine @RawLine)+ @BlankLine* | @BlankLine+ | @RawLine)")
  Rules[:_ExtendedSpecialChar] = rule_info("ExtendedSpecialChar", "&{ notes? } \"^\"")
  Rules[:_NoteReference] = rule_info("NoteReference", "&{ notes? } RawNoteReference:ref { note_for ref }")
  Rules[:_RawNoteReference] = rule_info("RawNoteReference", "\"[^\" < (!@Newline !\"]\" .)+ > \"]\" { text }")
  Rules[:_Note] = rule_info("Note", "&{ notes? } @NonindentSpace RawNoteReference:ref \":\" @Sp @StartList:a RawNoteBlock:i { a.concat i } (&Indent RawNoteBlock:i { a.concat i })* { @footnotes[ref] = paragraph a                    nil                 }")
  Rules[:_InlineNote] = rule_info("InlineNote", "&{ notes? } \"^[\" @StartList:a (!\"]\" Inline:l { a << l })+ \"]\" { ref = [:inline, @note_order.length]                @footnotes[ref] = paragraph a                 note_for ref              }")
  Rules[:_Notes] = rule_info("Notes", "(Note | SkipBlock)*")
  Rules[:_RawNoteBlock] = rule_info("RawNoteBlock", "@StartList:a (!@BlankLine OptionallyIndentedLine:l { a << l })+ < @BlankLine* > { a << text } { a }")
  Rules[:_CodeFence] = rule_info("CodeFence", "&{ github? } Ticks3 (@Sp StrChunk:format)? Spnl < ((!\"`\" Nonspacechar)+ | !Ticks3 /`+/ | Spacechar | @Newline)+ > Ticks3 @Sp @Newline* { verbatim = RDoc::Markup::Verbatim.new text               verbatim.format = format.intern if format.instance_of?(String)               verbatim             }")
  Rules[:_Table] = rule_info("Table", "&{ github? } TableRow:header TableLine:line TableRow+:body { table = RDoc::Markup::Table.new(header, line, body) }")
  Rules[:_TableRow] = rule_info("TableRow", "TableItem+:row \"|\" @Newline { row }")
  Rules[:_TableItem] = rule_info("TableItem", "\"|\" < (!\"|\" !@Newline .)+ > { text.strip }")
  Rules[:_TableLine] = rule_info("TableLine", "TableColumn+:line \"|\" @Newline { line }")
  Rules[:_TableColumn] = rule_info("TableColumn", "\"|\" < (\"-\"+ \":\"? | \":\" \"-\"*) > { text.start_with?(\":\") ? :left :                 text.end_with?(\":\") ? :right : nil               }")
  Rules[:_DefinitionList] = rule_info("DefinitionList", "&{ definition_lists? } DefinitionListItem+:list { RDoc::Markup::List.new :NOTE, *list.flatten }")
  Rules[:_DefinitionListItem] = rule_info("DefinitionListItem", "DefinitionListLabel+:label DefinitionListDefinition+:defns { list_items = []                        list_items <<                          RDoc::Markup::ListItem.new(label, defns.shift)                         list_items.concat defns.map { |defn|                          RDoc::Markup::ListItem.new nil, defn                        } unless list_items.empty?                         list_items                      }")
  Rules[:_DefinitionListLabel] = rule_info("DefinitionListLabel", "StrChunk:label @Sp @Newline { label }")
  Rules[:_DefinitionListDefinition] = rule_info("DefinitionListDefinition", "@NonindentSpace \":\" @Space Inlines:a @BlankLine+ { paragraph a }")
  # :startdoc:
end
