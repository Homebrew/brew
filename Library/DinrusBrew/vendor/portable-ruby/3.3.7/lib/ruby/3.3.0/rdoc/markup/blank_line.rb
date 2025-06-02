# frozen_string_literal: true
##
# An empty line.  This class is a singleton.

class RDoc::Markup::BlankLine

  @instance = new

  ##
  # RDoc::Markup::BlankLine is a singleton

  def self.new
    @instance
  end

  ##
  # Calls #accept_blank_line on +visitor+

  def accept visitor
    visitor.accept_blank_line self
  end

  def pretty_print q # :nodoc:
    q.text 'blankline'
  end

end
