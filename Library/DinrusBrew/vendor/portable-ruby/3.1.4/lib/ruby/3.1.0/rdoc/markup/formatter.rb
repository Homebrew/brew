# frozen_string_literal: true
##
# Base class for RDoc markup formatters
#
# Formatters are a visitor that converts an RDoc::Markup tree (from a comment)
# into some kind of output.  RDoc ships with formatters for converting back to
# rdoc, ANSI text, HTML, a Table of Contents and other formats.
#
# If you'd like to write your own Formatter use
# RDoc::Markup::FormatterTestCase.  If you're writing a text-output formatter
# use RDoc::Markup::TextFormatterTestCase which provides extra test cases.

class RDoc::Markup::Formatter

  ##
  # Tag for inline markup containing a +bit+ for the bitmask and the +on+ and
  # +off+ triggers.

  InlineTag = Struct.new(:bit, :on, :off)

  ##
  # Converts a target url to one that is relative to a given path

  def self.gen_relative_url path, target
    from        = File.dirname path
    to, to_file = File.split target

    from = from.split "/"
    to   = to.split "/"

    from.delete '.'
    to.delete '.'

    while from.size > 0 and to.size > 0 and from[0] == to[0] do
      from.shift
      to.shift
    end

    from.fill ".."
    from.concat to
    from << to_file
    File.join(*from)
  end

  ##
  # Creates a new Formatter

  def initialize options, markup = nil
    @options = options

    @markup = markup || RDoc::Markup.new
    @am     = @markup.attribute_manager
    @am.add_regexp_handling(/<br>/, :HARD_BREAK)

    @attributes = @am.attributes

    @attr_tags = []

    @in_tt = 0
    @tt_bit = @attributes.bitmap_for :TT

    @hard_break = ''
    @from_path = '.'
  end

  ##
  # Adds +document+ to the output

  def accept_document document
    document.parts.each do |item|
      case item
      when RDoc::Markup::Document then # HACK
        accept_document item
      else
        item.accept self
      end
    end
  end

  ##
  # Adds a regexp handling for links of the form rdoc-...:

  def add_regexp_handling_RDOCLINK
    @markup.add_regexp_handling(/rdoc-[a-z]+:[^\s\]]+/, :RDOCLINK)
  end

  ##
  # Adds a regexp handling for links of the form {<text>}[<url>] and
  # <word>[<url>]

  def add_regexp_handling_TIDYLINK
    @markup.add_regexp_handling(/(?:
                                  \{.*?\} |    # multi-word label
                                  \b[^\s{}]+? # single-word label
                                 )

                                 \[\S+?\]     # link target
                                /x, :TIDYLINK)
  end

  ##
  # Add a new set of tags for an attribute. We allow separate start and end
  # tags for flexibility

  def add_tag(name, start, stop)
    attr = @attributes.bitmap_for name
    @attr_tags << InlineTag.new(attr, start, stop)
  end

  ##
  # Allows +tag+ to be decorated with additional information.

  def annotate(tag)
    tag
  end

  ##
  # Marks up +content+

  def convert content
    @markup.convert content, self
  end

  ##
  # Converts flow items +flow+

  def convert_flow(flow)
    res = []

    flow.each do |item|
      case item
      when String then
        res << convert_string(item)
      when RDoc::Markup::AttrChanger then
        off_tags res, item
        on_tags res, item
      when RDoc::Markup::RegexpHandling then
        res << convert_regexp_handling(item)
      else
        raise "Unknown flow element: #{item.inspect}"
      end
    end

    res.join
  end

  ##
  # Converts added regexp handlings. See RDoc::Markup#add_regexp_handling

  def convert_regexp_handling target
    return target.text if in_tt?

    handled = false

    @attributes.each_name_of target.type do |name|
      method_name = "handle_regexp_#{name}"

      if respond_to? method_name then
        target.text = public_send method_name, target
        handled = true
      end
    end

    unless handled then
      target_name = @attributes.as_string target.type

      raise RDoc::Error, "Unhandled regexp handling #{target_name}: #{target}"
    end

    target.text
  end

  ##
  # Converts a string to be fancier if desired

  def convert_string string
    string
  end

  ##
  # Use ignore in your subclass to ignore the content of a node.
  #
  #   ##
  #   # We don't support raw nodes in ToNoRaw
  #
  #   alias accept_raw ignore

  def ignore *node
  end

  ##
  # Are we currently inside tt tags?

  def in_tt?
    @in_tt > 0
  end

  ##
  # Turns on tags for +item+ on +res+

  def on_tags res, item
    attr_mask = item.turn_on
    return if attr_mask.zero?

    @attr_tags.each do |tag|
      if attr_mask & tag.bit != 0 then
        res << annotate(tag.on)
        @in_tt += 1 if tt? tag
      end
    end
  end

  ##
  # Turns off tags for +item+ on +res+

  def off_tags res, item
    attr_mask = item.turn_off
    return if attr_mask.zero?

    @attr_tags.reverse_each do |tag|
      if attr_mask & tag.bit != 0 then
        @in_tt -= 1 if tt? tag
        res << annotate(tag.off)
      end
    end
  end

  ##
  # Extracts and a scheme, url and an anchor id from +url+ and returns them.

  def parse_url url
    case url
    when /^rdoc-label:([^:]*)(?::(.*))?/ then
      scheme = 'link'
      path   = "##{$1}"
      id     = " id=\"#{$2}\"" if $2
    when /([A-Za-z]+):(.*)/ then
      scheme = $1.downcase
      path   = $2
    when /^#/ then
    else
      scheme = 'http'
      path   = url
      url    = url
    end

    if scheme == 'link' then
      url = if path[0, 1] == '#' then # is this meaningful?
              path
            else
              self.class.gen_relative_url @from_path, path
            end
    end

    [scheme, url, id]
  end

  ##
  # Is +tag+ a tt tag?

  def tt? tag
    tag.bit == @tt_bit
  end

end

