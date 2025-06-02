# frozen_string_literal: true
require 'cgi'

##
# Outputs RDoc markup as HTML.

class RDoc::Markup::ToHtml < RDoc::Markup::Formatter

  include RDoc::Text

  # :section: Utilities

  ##
  # Maps RDoc::Markup::Parser::LIST_TOKENS types to HTML tags

  LIST_TYPE_TO_HTML = {
    :BULLET => ['<ul>',                                      '</ul>'],
    :LABEL  => ['<dl class="rdoc-list label-list">',         '</dl>'],
    :LALPHA => ['<ol style="list-style-type: lower-alpha">', '</ol>'],
    :NOTE   => ['<dl class="rdoc-list note-list">',          '</dl>'],
    :NUMBER => ['<ol>',                                      '</ol>'],
    :UALPHA => ['<ol style="list-style-type: upper-alpha">', '</ol>'],
  }

  attr_reader :res # :nodoc:
  attr_reader :in_list_entry # :nodoc:
  attr_reader :list # :nodoc:

  ##
  # The RDoc::CodeObject HTML is being generated for.  This is used to
  # generate namespaced URI fragments

  attr_accessor :code_object

  ##
  # Path to this document for relative links

  attr_accessor :from_path

  # :section:

  ##
  # Creates a new formatter that will output HTML

  def initialize options, markup = nil
    super

    @code_object = nil
    @from_path = ''
    @in_list_entry = nil
    @list = nil
    @th = nil
    @hard_break = "<br>\n"

    init_regexp_handlings

    init_tags
  end

  # :section: Regexp Handling
  #
  # These methods are used by regexp handling markup added by RDoc::Markup#add_regexp_handling.

  ##
  # Adds regexp handlings.

  def init_regexp_handlings
    # external links
    @markup.add_regexp_handling(/(?:link:|https?:|mailto:|ftp:|irc:|www\.)\S+\w/,
                                :HYPERLINK)
    init_link_notation_regexp_handlings
  end

  ##
  # Adds regexp handlings about link notations.

  def init_link_notation_regexp_handlings
    add_regexp_handling_RDOCLINK
    add_regexp_handling_TIDYLINK
  end

  def handle_RDOCLINK url # :nodoc:
    case url
    when /^rdoc-ref:/
      $'
    when /^rdoc-label:/
      text = $'

      text = case text
             when /\Alabel-/    then $'
             when /\Afootmark-/ then $'
             when /\Afoottext-/ then $'
             else                    text
             end

      gen_url url, text
    when /^rdoc-image:/
      "<img src=\"#{$'}\">"
    else
      url =~ /\Ardoc-[a-z]+:/

      $'
    end
  end

  ##
  # +target+ is a <code><br></code>

  def handle_regexp_HARD_BREAK target
    '<br>'
  end

  ##
  # +target+ is a potential link.  The following schemes are handled:
  #
  # <tt>mailto:</tt>::
  #   Inserted as-is.
  # <tt>http:</tt>::
  #   Links are checked to see if they reference an image. If so, that image
  #   gets inserted using an <tt><img></tt> tag. Otherwise a conventional
  #   <tt><a href></tt> is used.
  # <tt>link:</tt>::
  #   Reference to a local file relative to the output directory.

  def handle_regexp_HYPERLINK(target)
    url = target.text

    gen_url url, url
  end

  ##
  # +target+ is an rdoc-schemed link that will be converted into a hyperlink.
  #
  # For the +rdoc-ref+ scheme the named reference will be returned without
  # creating a link.
  #
  # For the +rdoc-label+ scheme the footnote and label prefixes are stripped
  # when creating a link.  All other contents will be linked verbatim.

  def handle_regexp_RDOCLINK target
    handle_RDOCLINK target.text
  end

  ##
  # This +target+ is a link where the label is different from the URL
  # <tt>label[url]</tt> or <tt>{long label}[url]</tt>

  def handle_regexp_TIDYLINK(target)
    text = target.text

    return text unless
      text =~ /^\{(.*)\}\[(.*?)\]$/ or text =~ /^(\S+)\[(.*?)\]$/

    label = $1
    url   = $2

    label = handle_RDOCLINK label if /^rdoc-image:/ =~ label

    gen_url url, label
  end

  # :section: Visitor
  #
  # These methods implement the HTML visitor.

  ##
  # Prepares the visitor for HTML generation

  def start_accepting
    @res = []
    @in_list_entry = []
    @list = []
  end

  ##
  # Returns the generated output

  def end_accepting
    @res.join
  end

  ##
  # Adds +block_quote+ to the output

  def accept_block_quote block_quote
    @res << "\n<blockquote>"

    block_quote.parts.each do |part|
      part.accept self
    end

    @res << "</blockquote>\n"
  end

  ##
  # Adds +paragraph+ to the output

  def accept_paragraph paragraph
    @res << "\n<p>"
    text = paragraph.text @hard_break
    text = text.gsub(/\r?\n/, ' ')
    @res << to_html(text)
    @res << "</p>\n"
  end

  ##
  # Adds +verbatim+ to the output

  def accept_verbatim verbatim
    text = verbatim.text.rstrip

    klass = nil

    content = if verbatim.ruby? or parseable? text then
                begin
                  tokens = RDoc::Parser::RipperStateLex.parse text
                  klass  = ' class="ruby"'

                  result = RDoc::TokenStream.to_html tokens
                  result = result + "\n" unless "\n" == result[-1]
                  result
                rescue
                  CGI.escapeHTML text
                end
              else
                CGI.escapeHTML text
              end

    if @options.pipe then
      @res << "\n<pre><code>#{CGI.escapeHTML text}\n</code></pre>\n"
    else
      @res << "\n<pre#{klass}>#{content}</pre>\n"
    end
  end

  ##
  # Adds +rule+ to the output

  def accept_rule rule
    @res << "<hr>\n"
  end

  ##
  # Prepares the visitor for consuming +list+

  def accept_list_start(list)
    @list << list.type
    @res << html_list_name(list.type, true)
    @in_list_entry.push false
  end

  ##
  # Finishes consumption of +list+

  def accept_list_end(list)
    @list.pop
    if tag = @in_list_entry.pop
      @res << tag
    end
    @res << html_list_name(list.type, false) << "\n"
  end

  ##
  # Prepares the visitor for consuming +list_item+

  def accept_list_item_start(list_item)
    if tag = @in_list_entry.last
      @res << tag
    end

    @res << list_item_start(list_item, @list.last)
  end

  ##
  # Finishes consumption of +list_item+

  def accept_list_item_end(list_item)
    @in_list_entry[-1] = list_end_for(@list.last)
  end

  ##
  # Adds +blank_line+ to the output

  def accept_blank_line(blank_line)
    # @res << annotate("<p />") << "\n"
  end

  ##
  # Adds +heading+ to the output.  The headings greater than 6 are trimmed to
  # level 6.

  def accept_heading heading
    level = [6, heading.level].min

    label = heading.label @code_object

    @res << if @options.output_decoration
              "\n<h#{level} id=\"#{label}\">"
            else
              "\n<h#{level}>"
            end
    @res << to_html(heading.text)
    unless @options.pipe then
      @res << "<span><a href=\"##{label}\">&para;</a>"
      @res << " <a href=\"#top\">&uarr;</a></span>"
    end
    @res << "</h#{level}>\n"
  end

  ##
  # Adds +raw+ to the output

  def accept_raw raw
    @res << raw.parts.join("\n")
  end

  ##
  # Adds +table+ to the output

  def accept_table header, body, aligns
    @res << "\n<table role=\"table\">\n<thead>\n<tr>\n"
    header.zip(aligns) do |text, align|
      @res << '<th'
      @res << ' align="' << align << '"' if align
      @res << '>' << CGI.escapeHTML(text) << "</th>\n"
    end
    @res << "</tr>\n</thead>\n<tbody>\n"
    body.each do |row|
      @res << "<tr>\n"
      row.zip(aligns) do |text, align|
        @res << '<td'
        @res << ' align="' << align << '"' if align
        @res << '>' << CGI.escapeHTML(text) << "</td>\n"
      end
      @res << "</tr>\n"
    end
    @res << "</tbody>\n</table>\n"
  end

  # :section: Utilities

  ##
  # CGI-escapes +text+

  def convert_string(text)
    CGI.escapeHTML text
  end

  ##
  # Generate a link to +url+ with content +text+.  Handles the special cases
  # for img: and link: described under handle_regexp_HYPERLINK

  def gen_url url, text
    scheme, url, id = parse_url url

    if %w[http https link].include?(scheme) and
       url =~ /\.(gif|png|jpg|jpeg|bmp)$/ then
      "<img src=\"#{url}\" />"
    else
      if scheme != 'link' and %r%\A((?!https?:)(?:[^/#]*/)*+)([^/#]+)\.(rb|rdoc|md)(?=\z|#)%i =~ url
        url = "#$1#{$2.tr('.', '_')}_#$3.html#$'"
      end

      text = text.sub %r%^#{scheme}:/*%i, ''
      text = text.sub %r%^[*\^](\d+)$%,   '\1'

      link = "<a#{id} href=\"#{url}\">#{text}</a>"

      link = "<sup>#{link}</sup>" if /"foot/ =~ id

      link
    end
  end

  ##
  # Determines the HTML list element for +list_type+ and +open_tag+

  def html_list_name(list_type, open_tag)
    tags = LIST_TYPE_TO_HTML[list_type]
    raise RDoc::Error, "Invalid list type: #{list_type.inspect}" unless tags
    tags[open_tag ? 0 : 1]
  end

  ##
  # Maps attributes to HTML tags

  def init_tags
    add_tag :BOLD, "<strong>", "</strong>"
    add_tag :TT,   "<code>",   "</code>"
    add_tag :EM,   "<em>",     "</em>"
  end

  ##
  # Returns the HTML tag for +list_type+, possible using a label from
  # +list_item+

  def list_item_start(list_item, list_type)
    case list_type
    when :BULLET, :LALPHA, :NUMBER, :UALPHA then
      "<li>"
    when :LABEL, :NOTE then
      Array(list_item.label).map do |label|
        "<dt>#{to_html label}\n"
      end.join << "<dd>"
    else
      raise RDoc::Error, "Invalid list type: #{list_type.inspect}"
    end
  end

  ##
  # Returns the HTML end-tag for +list_type+

  def list_end_for(list_type)
    case list_type
    when :BULLET, :LALPHA, :NUMBER, :UALPHA then
      "</li>"
    when :LABEL, :NOTE then
      "</dd>"
    else
      raise RDoc::Error, "Invalid list type: #{list_type.inspect}"
    end
  end

  ##
  # Returns true if text is valid ruby syntax

  def parseable? text
    verbose, $VERBOSE = $VERBOSE, nil
    eval("BEGIN {return true}\n#{text}")
  rescue SyntaxError
    false
  ensure
    $VERBOSE = verbose
  end

  ##
  # Converts +item+ to HTML using RDoc::Text#to_html

  def to_html item
    super convert_flow @am.flow item
  end

end

