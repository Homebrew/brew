# frozen_string_literal: true
##
# Outputs RDoc markup as RDoc markup! (mostly)

class RDoc::Markup::ToRdoc < RDoc::Markup::Formatter

  ##
  # Current indent amount for output in characters

  attr_accessor :indent

  ##
  # Output width in characters

  attr_accessor :width

  ##
  # Stack of current list indexes for alphabetic and numeric lists

  attr_reader :list_index

  ##
  # Stack of list types

  attr_reader :list_type

  ##
  # Stack of list widths for indentation

  attr_reader :list_width

  ##
  # Prefix for the next list item.  See #use_prefix

  attr_reader :prefix

  ##
  # Output accumulator

  attr_reader :res

  ##
  # Creates a new formatter that will output (mostly) \RDoc markup

  def initialize markup = nil
    super nil, markup

    @markup.add_regexp_handling(/\\\S/, :SUPPRESSED_CROSSREF)
    @width = 78
    init_tags

    @headings = {}
    @headings.default = []

    @headings[1] = ['= ',      '']
    @headings[2] = ['== ',     '']
    @headings[3] = ['=== ',    '']
    @headings[4] = ['==== ',   '']
    @headings[5] = ['===== ',  '']
    @headings[6] = ['====== ', '']

    @hard_break = "\n"
  end

  ##
  # Maps attributes to HTML sequences

  def init_tags
    add_tag :BOLD, "<b>", "</b>"
    add_tag :TT,   "<tt>", "</tt>"
    add_tag :EM,   "<em>", "</em>"
  end

  ##
  # Adds +blank_line+ to the output

  def accept_blank_line blank_line
    @res << "\n"
  end

  ##
  # Adds +paragraph+ to the output

  def accept_block_quote block_quote
    @indent += 2

    block_quote.parts.each do |part|
      @prefix = '> '

      part.accept self
    end

    @indent -= 2
  end

  ##
  # Adds +heading+ to the output

  def accept_heading heading
    use_prefix or @res << ' ' * @indent
    @res << @headings[heading.level][0]
    @res << attributes(heading.text)
    @res << @headings[heading.level][1]
    @res << "\n"
  end

  ##
  # Finishes consumption of +list+

  def accept_list_end list
    @list_index.pop
    @list_type.pop
    @list_width.pop
  end

  ##
  # Finishes consumption of +list_item+

  def accept_list_item_end list_item
    width = case @list_type.last
            when :BULLET then
              2
            when :NOTE, :LABEL then
              if @prefix then
                @res << @prefix.strip
                @prefix = nil
              end

              @res << "\n"
              2
            else
              bullet = @list_index.last.to_s
              @list_index[-1] = @list_index.last.succ
              bullet.length + 2
            end

    @indent -= width
  end

  ##
  # Prepares the visitor for consuming +list_item+

  def accept_list_item_start list_item
    type = @list_type.last

    case type
    when :NOTE, :LABEL then
      bullets = Array(list_item.label).map do |label|
        attributes(label).strip
      end.join "\n"

      bullets << ":\n" unless bullets.empty?

      @prefix = ' ' * @indent
      @indent += 2
      @prefix << bullets + (' ' * @indent)
    else
      bullet = type == :BULLET ? '*' :  @list_index.last.to_s + '.'
      @prefix = (' ' * @indent) + bullet.ljust(bullet.length + 1)
      width = bullet.length + 1
      @indent += width
    end
  end

  ##
  # Prepares the visitor for consuming +list+

  def accept_list_start list
    case list.type
    when :BULLET then
      @list_index << nil
      @list_width << 1
    when :LABEL, :NOTE then
      @list_index << nil
      @list_width << 2
    when :LALPHA then
      @list_index << 'a'
      @list_width << list.items.length.to_s.length
    when :NUMBER then
      @list_index << 1
      @list_width << list.items.length.to_s.length
    when :UALPHA then
      @list_index << 'A'
      @list_width << list.items.length.to_s.length
    else
      raise RDoc::Error, "invalid list type #{list.type}"
    end

    @list_type << list.type
  end

  ##
  # Adds +paragraph+ to the output

  def accept_paragraph paragraph
    text = paragraph.text @hard_break
    wrap attributes text
  end

  ##
  # Adds +paragraph+ to the output

  def accept_indented_paragraph paragraph
    @indent += paragraph.indent
    text = paragraph.text @hard_break
    wrap attributes text
    @indent -= paragraph.indent
  end

  ##
  # Adds +raw+ to the output

  def accept_raw raw
    @res << raw.parts.join("\n")
  end

  ##
  # Adds +rule+ to the output

  def accept_rule rule
    use_prefix or @res << ' ' * @indent
    @res << '-' * (@width - @indent)
    @res << "\n"
  end

  ##
  # Outputs +verbatim+ indented 2 columns

  def accept_verbatim verbatim
    indent = ' ' * (@indent + 2)

    verbatim.parts.each do |part|
      @res << indent unless part == "\n"
      @res << part
    end

    @res << "\n"
  end

  ##
  # Adds +table+ to the output

  def accept_table header, body, aligns
    widths = header.zip(body) do |h, b|
      [h.size, b.size].max
    end
    aligns = aligns.map do |a|
      case a
      when nil
        :center
      when :left
        :ljust
      when :right
        :rjust
      end
    end
    @res << header.zip(widths, aligns) do |h, w, a|
      h.__send__(a, w)
    end.join("|").rstrip << "\n"
    @res << widths.map {|w| "-" * w }.join("|") << "\n"
    body.each do |row|
      @res << row.zip(widths, aligns) do |t, w, a|
        t.__send__(a, w)
      end.join("|").rstrip << "\n"
    end
  end

  ##
  # Applies attribute-specific markup to +text+ using RDoc::AttributeManager

  def attributes text
    flow = @am.flow text.dup
    convert_flow flow
  end

  ##
  # Returns the generated output

  def end_accepting
    @res.join
  end

  ##
  # Removes preceding \\ from the suppressed crossref +target+

  def handle_regexp_SUPPRESSED_CROSSREF target
    text = target.text
    text = text.sub('\\', '') unless in_tt?
    text
  end

  ##
  # Adds a newline to the output

  def handle_regexp_HARD_BREAK target
    "\n"
  end

  ##
  # Prepares the visitor for text generation

  def start_accepting
    @res = [""]
    @indent = 0
    @prefix = nil

    @list_index = []
    @list_type  = []
    @list_width = []
  end

  ##
  # Adds the stored #prefix to the output and clears it.  Lists generate a
  # prefix for later consumption.

  def use_prefix
    prefix, @prefix = @prefix, nil
    @res << prefix if prefix

    prefix
  end

  ##
  # Wraps +text+ to #width

  def wrap text
    return unless text && !text.empty?

    text_len = @width - @indent

    text_len = 20 if text_len < 20

    re = /^(.{0,#{text_len}})[ \n]/
    next_prefix = ' ' * @indent

    prefix = @prefix || next_prefix
    @prefix = nil

    @res << prefix

    while text.length > text_len
      if text =~ re then
        @res << $1
        text.slice!(0, $&.length)
      else
        @res << text.slice!(0, text_len)
      end

      @res << "\n" << next_prefix
    end

    if text.empty? then
      @res.pop
      @res.pop
    else
      @res << text
      @res << "\n"
    end
  end

end

