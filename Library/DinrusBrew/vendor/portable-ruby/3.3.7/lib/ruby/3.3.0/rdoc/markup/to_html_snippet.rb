# frozen_string_literal: true
##
# Outputs RDoc markup as paragraphs with inline markup only.

class RDoc::Markup::ToHtmlSnippet < RDoc::Markup::ToHtml

  ##
  # After this many characters the input will be cut off.

  attr_reader :character_limit

  ##
  # The number of characters seen so far.

  attr_reader :characters # :nodoc:

  ##
  # The attribute bitmask

  attr_reader :mask

  ##
  # After this many paragraphs the input will be cut off.

  attr_reader :paragraph_limit

  ##
  # Count of paragraphs found

  attr_reader :paragraphs

  ##
  # Creates a new ToHtmlSnippet formatter that will cut off the input on the
  # next word boundary after the given number of +characters+ or +paragraphs+
  # of text have been encountered.

  def initialize options, characters = 100, paragraphs = 3, markup = nil
    super options, markup

    @character_limit = characters
    @paragraph_limit = paragraphs

    @characters = 0
    @mask       = 0
    @paragraphs = 0

    @markup.add_regexp_handling RDoc::CrossReference::CROSSREF_REGEXP, :CROSSREF
  end

  ##
  # Adds +heading+ to the output as a paragraph

  def accept_heading heading
    @res << "<p>#{to_html heading.text}\n"

    add_paragraph
  end

  ##
  # Raw sections are untrusted and ignored

  alias accept_raw ignore

  ##
  # Rules are ignored

  alias accept_rule ignore

  ##
  # Adds +paragraph+ to the output

  def accept_paragraph paragraph
    para = @in_list_entry.last || "<p>"

    text = paragraph.text @hard_break

    @res << "#{para}#{to_html text}\n"

    add_paragraph
  end

  ##
  # Finishes consumption of +list_item+

  def accept_list_item_end list_item
  end

  ##
  # Prepares the visitor for consuming +list_item+

  def accept_list_item_start list_item
    @res << list_item_start(list_item, @list.last)
  end

  ##
  # Prepares the visitor for consuming +list+

  def accept_list_start list
    @list << list.type
    @res << html_list_name(list.type, true)
    @in_list_entry.push ''
  end

  ##
  # Adds +verbatim+ to the output

  def accept_verbatim verbatim
    throw :done if @characters >= @character_limit
    input = verbatim.text.rstrip

    text = truncate input
    text << ' ...' unless text == input

    super RDoc::Markup::Verbatim.new text

    add_paragraph
  end

  ##
  # Prepares the visitor for HTML snippet generation

  def start_accepting
    super

    @characters = 0
  end

  ##
  # Removes escaping from the cross-references in +target+

  def handle_regexp_CROSSREF target
    target.text.sub(/\A\\/, '')
  end

  ##
  # +target+ is a <code><br></code>

  def handle_regexp_HARD_BREAK target
    @characters -= 4
    '<br>'
  end

  ##
  # Lists are paragraphs, but notes and labels have a separator

  def list_item_start list_item, list_type
    throw :done if @characters >= @character_limit

    case list_type
    when :BULLET, :LALPHA, :NUMBER, :UALPHA then
      "<p>"
    when :LABEL, :NOTE then
      labels = Array(list_item.label).map do |label|
        to_html label
      end.join ', '

      labels << " &mdash; " unless labels.empty?

      start = "<p>#{labels}"
      @characters += 1 # try to include the label
      start
    else
      raise RDoc::Error, "Invalid list type: #{list_type.inspect}"
    end
  end

  ##
  # Returns just the text of +link+, +url+ is only used to determine the link
  # type.

  def gen_url url, text
    if url =~ /^rdoc-label:([^:]*)(?::(.*))?/ then
      type = "link"
    elsif url =~ /([A-Za-z]+):(.*)/ then
      type = $1
    else
      type = "http"
    end

    if (type == "http" or type == "https" or type == "link") and
       url =~ /\.(gif|png|jpg|jpeg|bmp)$/ then
      ''
    else
      text.sub(%r%^#{type}:/*%, '')
    end
  end

  ##
  # In snippets, there are no lists

  def html_list_name list_type, open_tag
    ''
  end

  ##
  # Throws +:done+ when paragraph_limit paragraphs have been encountered

  def add_paragraph
    @paragraphs += 1

    throw :done if @paragraphs >= @paragraph_limit
  end

  ##
  # Marks up +content+

  def convert content
    catch :done do
      return super
    end

    end_accepting
  end

  ##
  # Converts flow items +flow+

  def convert_flow flow
    throw :done if @characters >= @character_limit

    res = []
    @mask = 0

    flow.each do |item|
      case item
      when RDoc::Markup::AttrChanger then
        off_tags res, item
        on_tags  res, item
      when String then
        text = convert_string item
        res << truncate(text)
      when RDoc::Markup::RegexpHandling then
        text = convert_regexp_handling item
        res << truncate(text)
      else
        raise "Unknown flow element: #{item.inspect}"
      end

      if @characters >= @character_limit then
        off_tags res, RDoc::Markup::AttrChanger.new(0, @mask)
        break
      end
    end

    res << ' ...' if @characters >= @character_limit

    res.join
  end

  ##
  # Maintains a bitmask to allow HTML elements to be closed properly.  See
  # RDoc::Markup::Formatter.

  def on_tags res, item
    @mask ^= item.turn_on

    super
  end

  ##
  # Maintains a bitmask to allow HTML elements to be closed properly.  See
  # RDoc::Markup::Formatter.

  def off_tags res, item
    @mask ^= item.turn_off

    super
  end

  ##
  # Truncates +text+ at the end of the first word after the character_limit.

  def truncate text
    length = text.length
    characters = @characters
    @characters += length

    return text if @characters < @character_limit

    remaining = @character_limit - characters

    text =~ /\A(.{#{remaining},}?)(\s|$)/m # TODO word-break instead of \s?

    $1
  end

end
