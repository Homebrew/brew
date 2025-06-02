# frozen_string_literal: true
##
# Extracts just the RDoc::Markup::Heading elements from a
# RDoc::Markup::Document to help build a table of contents

class RDoc::Markup::ToTableOfContents < RDoc::Markup::Formatter

  @to_toc = nil

  ##
  # Singleton for table-of-contents generation

  def self.to_toc
    @to_toc ||= new
  end

  ##
  # Output accumulator

  attr_reader :res

  ##
  # Omits headings with a level less than the given level.

  attr_accessor :omit_headings_below

  def initialize # :nodoc:
    super nil

    @omit_headings_below = nil
  end

  ##
  # Adds +document+ to the output, using its heading cutoff if present

  def accept_document document
    @omit_headings_below = document.omit_headings_below

    super
  end

  ##
  # Adds +heading+ to the table of contents

  def accept_heading heading
    @res << heading unless suppressed? heading
  end

  ##
  # Returns the table of contents

  def end_accepting
    @res
  end

  ##
  # Prepares the visitor for text generation

  def start_accepting
    @omit_headings_below = nil
    @res = []
  end

  ##
  # Returns true if +heading+ is below the display threshold

  def suppressed? heading
    return false unless @omit_headings_below

    heading.level > @omit_headings_below
  end

  # :stopdoc:
  alias accept_block_quote     ignore
  alias accept_raw             ignore
  alias accept_rule            ignore
  alias accept_blank_line      ignore
  alias accept_paragraph       ignore
  alias accept_verbatim        ignore
  alias accept_list_end        ignore
  alias accept_list_item_start ignore
  alias accept_list_item_end   ignore
  alias accept_list_end_bullet ignore
  alias accept_list_start      ignore
  alias accept_table           ignore
  # :startdoc:

end

