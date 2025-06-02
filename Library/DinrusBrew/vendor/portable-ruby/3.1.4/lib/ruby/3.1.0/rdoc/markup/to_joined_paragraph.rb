# frozen_string_literal: true
##
# Joins the parts of an RDoc::Markup::Paragraph into a single String.
#
# This allows for easier maintenance and testing of Markdown support.
#
# This formatter only works on Paragraph instances.  Attempting to process
# other markup syntax items will not work.

class RDoc::Markup::ToJoinedParagraph < RDoc::Markup::Formatter

  def initialize # :nodoc:
    super nil
  end

  def start_accepting # :nodoc:
  end

  def end_accepting # :nodoc:
  end

  ##
  # Converts the parts of +paragraph+ to a single entry.

  def accept_paragraph paragraph
    parts = paragraph.parts.chunk do |part|
      String === part
    end.map do |string, chunk|
      string ? chunk.join.rstrip : chunk
    end.flatten

    paragraph.parts.replace parts
  end

  alias accept_block_quote     ignore
  alias accept_heading         ignore
  alias accept_list_end        ignore
  alias accept_list_item_end   ignore
  alias accept_list_item_start ignore
  alias accept_list_start      ignore
  alias accept_raw             ignore
  alias accept_rule            ignore
  alias accept_verbatim        ignore
  alias accept_table           ignore

end

