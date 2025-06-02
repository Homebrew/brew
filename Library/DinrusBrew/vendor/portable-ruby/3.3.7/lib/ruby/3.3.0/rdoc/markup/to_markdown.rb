# frozen_string_literal: true
# :markup: markdown

##
# Outputs parsed markup as Markdown

class RDoc::Markup::ToMarkdown < RDoc::Markup::ToRdoc

  ##
  # Creates a new formatter that will output Markdown format text

  def initialize markup = nil
    super

    @headings[1] = ['# ',      '']
    @headings[2] = ['## ',     '']
    @headings[3] = ['### ',    '']
    @headings[4] = ['#### ',   '']
    @headings[5] = ['##### ',  '']
    @headings[6] = ['###### ', '']

    add_regexp_handling_RDOCLINK
    add_regexp_handling_TIDYLINK

    @hard_break = "  \n"
  end

  ##
  # Maps attributes to HTML sequences

  def init_tags
    add_tag :BOLD, '**', '**'
    add_tag :EM,   '*',  '*'
    add_tag :TT,   '`',  '`'
  end

  ##
  # Adds a newline to the output

  def handle_regexp_HARD_BREAK target
    "  \n"
  end

  ##
  # Finishes consumption of `list`

  def accept_list_end list
    @res << "\n"

    super
  end

  ##
  # Finishes consumption of `list_item`

  def accept_list_item_end list_item
    width = case @list_type.last
            when :BULLET then
              4
            when :NOTE, :LABEL then
              use_prefix

              4
            else
              @list_index[-1] = @list_index.last.succ
              4
            end

    @indent -= width
  end

  ##
  # Prepares the visitor for consuming `list_item`

  def accept_list_item_start list_item
    type = @list_type.last

    case type
    when :NOTE, :LABEL then
      bullets = Array(list_item.label).map do |label|
        attributes(label).strip
      end.join "\n"

      bullets << "\n:"

      @prefix = ' ' * @indent
      @indent += 4
      @prefix << bullets + (' ' * (@indent - 1))
    else
      bullet = type == :BULLET ? '*' : @list_index.last.to_s + '.'
      @prefix = (' ' * @indent) + bullet.ljust(4)

      @indent += 4
    end
  end

  ##
  # Prepares the visitor for consuming `list`

  def accept_list_start list
    case list.type
    when :BULLET, :LABEL, :NOTE then
      @list_index << nil
    when :LALPHA, :NUMBER, :UALPHA then
      @list_index << 1
    else
      raise RDoc::Error, "invalid list type #{list.type}"
    end

    @list_width << 4
    @list_type << list.type
  end

  ##
  # Adds `rule` to the output

  def accept_rule rule
    use_prefix or @res << ' ' * @indent
    @res << '-' * 3
    @res << "\n"
  end

  ##
  # Outputs `verbatim` indented 4 columns

  def accept_verbatim verbatim
    indent = ' ' * (@indent + 4)

    verbatim.parts.each do |part|
      @res << indent unless part == "\n"
      @res << part
    end

    @res << "\n"
  end

  ##
  # Creates a Markdown-style URL from +url+ with +text+.

  def gen_url url, text
    scheme, url, = parse_url url

    "[#{text.sub(%r{^#{scheme}:/*}i, '')}](#{url})"
  end

  ##
  # Handles <tt>rdoc-</tt> type links for footnotes.

  def handle_rdoc_link url
    case url
    when /^rdoc-ref:/ then
      $'
    when /^rdoc-label:footmark-(\d+)/ then
      "[^#{$1}]:"
    when /^rdoc-label:foottext-(\d+)/ then
      "[^#{$1}]"
    when /^rdoc-label:label-/ then
      gen_url url, $'
    when /^rdoc-image:/ then
      "![](#{$'})"
    when /^rdoc-[a-z]+:/ then
      $'
    end
  end

  ##
  # Converts the RDoc markup tidylink into a Markdown.style link.

  def handle_regexp_TIDYLINK target
    text = target.text

    return text unless text =~ /\{(.*?)\}\[(.*?)\]/ or text =~ /(\S+)\[(.*?)\]/

    label = $1
    url   = $2

    if url =~ /^rdoc-label:foot/ then
      handle_rdoc_link url
    else
      gen_url url, label
    end
  end

  ##
  # Converts the rdoc-...: links into a Markdown.style links.

  def handle_regexp_RDOCLINK target
    handle_rdoc_link target.text
  end

end
