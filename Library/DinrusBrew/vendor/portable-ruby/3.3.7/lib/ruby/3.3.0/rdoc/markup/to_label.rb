# frozen_string_literal: true
require 'cgi/util'

##
# Creates HTML-safe labels suitable for use in id attributes.  Tidylinks are
# converted to their link part and cross-reference links have the suppression
# marks removed (\\SomeClass is converted to SomeClass).

class RDoc::Markup::ToLabel < RDoc::Markup::Formatter

  attr_reader :res # :nodoc:

  ##
  # Creates a new formatter that will output HTML-safe labels

  def initialize markup = nil
    super nil, markup

    @markup.add_regexp_handling RDoc::CrossReference::CROSSREF_REGEXP, :CROSSREF
    @markup.add_regexp_handling(/(((\{.*?\})|\b\S+?)\[\S+?\])/, :TIDYLINK)

    add_tag :BOLD, '', ''
    add_tag :TT,   '', ''
    add_tag :EM,   '', ''

    @res = []
  end

  ##
  # Converts +text+ to an HTML-safe label

  def convert text
    label = convert_flow @am.flow text

    CGI.escape(label).gsub('%', '-').sub(/^-/, '')
  end

  ##
  # Converts the CROSSREF +target+ to plain text, removing the suppression
  # marker, if any

  def handle_regexp_CROSSREF target
    text = target.text

    text.sub(/^\\/, '')
  end

  ##
  # Converts the TIDYLINK +target+ to just the text part

  def handle_regexp_TIDYLINK target
    text = target.text

    return text unless text =~ /\{(.*?)\}\[(.*?)\]/ or text =~ /(\S+)\[(.*?)\]/

    $1
  end

  alias accept_blank_line         ignore
  alias accept_block_quote        ignore
  alias accept_heading            ignore
  alias accept_list_end           ignore
  alias accept_list_item_end      ignore
  alias accept_list_item_start    ignore
  alias accept_list_start         ignore
  alias accept_paragraph          ignore
  alias accept_raw                ignore
  alias accept_rule               ignore
  alias accept_verbatim           ignore
  alias end_accepting             ignore
  alias handle_regexp_HARD_BREAK  ignore
  alias start_accepting           ignore

end
